import Foundation

protocol WallpaperCatalogProviding {
    func loadCachedAnimeCatalog() async -> [CatalogWallpaper]?
    func fetchAnimeCatalog() async throws -> [CatalogWallpaper]
    func resolveDownloadURL(for wallpaper: CatalogWallpaper) async throws -> URL
}

actor WallpaperWaifuCatalogProvider: WallpaperCatalogProviding {
    private let session: URLSession
    private let baseSiteURL = URL(string: "https://wallpaperwaifu.com")!
    private let animeListingURL = URL(string: "https://wallpaperwaifu.com/anime/")!
    private var downloadURLCache: [String: URL] = [:]
    private var didLoadDownloadURLCache = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadCachedAnimeCatalog() async -> [CatalogWallpaper]? {
        guard let cacheURL = try? catalogCacheURL() else {
            return nil
        }
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        guard let envelope = try? JSONDecoder().decode(CatalogCacheEnvelope.self, from: data) else {
            return nil
        }
        return envelope.wallpapers.isEmpty ? nil : envelope.wallpapers
    }

    func fetchAnimeCatalog() async throws -> [CatalogWallpaper] {
        if let viaAPI = try await fetchAnimeCatalogViaWordPressAPI(), !viaAPI.isEmpty {
            try persistCatalog(viaAPI)
            return viaAPI
        }

        let viaHTML = try await fetchAnimeCatalogViaHTML()
        if viaHTML.isEmpty {
            throw URLError(.cannotParseResponse)
        }
        try persistCatalog(viaHTML)
        return viaHTML
    }

    func resolveDownloadURL(for wallpaper: CatalogWallpaper) async throws -> URL {
        if let source = wallpaper.sources.first {
            return source.url
        }

        guard let sourcePageURL = wallpaper.sourcePageURL else {
            throw URLError(.badURL)
        }

        try loadDownloadURLCacheIfNeeded()
        if let cached = downloadURLCache[sourcePageURL.absoluteString] {
            if let preferredVariant = preferredCachedVariant(for: cached),
               await isPlayableURLReachable(preferredVariant) {
                downloadURLCache[sourcePageURL.absoluteString] = preferredVariant
                try persistDownloadURLCache()
                return preferredVariant
            }
            return cached
        }

        let candidates = try await downloadCandidates(for: sourcePageURL)
        guard !candidates.isEmpty else {
            throw URLError(.badURL)
        }

        for candidate in candidates {
            if await isPlayableURLReachable(candidate) {
                downloadURLCache[sourcePageURL.absoluteString] = candidate
                try persistDownloadURLCache()
                return candidate
            }
        }

        // Fallback: keep best candidate even when HEAD/Range checks are blocked.
        let fallback = candidates[0]
        downloadURLCache[sourcePageURL.absoluteString] = fallback
        try persistDownloadURLCache()
        return fallback
    }

    private func preferredCachedVariant(for url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        if ext == "webm" {
            return replacingPathExtension(of: url, with: "mp4")
        }
        return nil
    }

    private func fetchAnimeCatalogViaWordPressAPI() async throws -> [CatalogWallpaper]? {
        let categoryID = (try? await fetchAnimeCategoryID()) ?? 4
        var page = 1
        var totalPages = 1
        var wallpapers: [CatalogWallpaper] = []

        while page <= totalPages {
            let postsURL = makeWPURL(
                path: "wp/v2/posts",
                queryItems: [
                    URLQueryItem(name: "categories", value: String(categoryID)),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "_embed", value: "1"),
                ]
            )
            let (data, response) = try await fetchData(from: postsURL)

            if let totalHeader = response.value(forHTTPHeaderField: "X-WP-TotalPages"),
               let parsedTotalPages = Int(totalHeader),
               parsedTotalPages > 0 {
                totalPages = parsedTotalPages
            }

            let posts = try JSONDecoder().decode([WordPressPostSummary].self, from: data)
            if posts.isEmpty {
                break
            }

            for post in posts {
                guard let postURL = URL(string: post.link) else {
                    continue
                }

                let title = normalizedTitle(post.title.rendered, fallback: titleFromSlug(post.slug))
                let preview = post.embedded?.featuredMedia?.first?.sourceURL.flatMap(URL.init(string:))
                wallpapers.append(
                    CatalogWallpaper(
                        id: "waifu-\(post.slug)",
                        title: title,
                        category: "Anime",
                        attribution: "WallpaperWaifu",
                        previewImageURL: preview,
                        sourcePageURL: postURL,
                        sources: []
                    )
                )
            }

            if posts.count < 100 && response.value(forHTTPHeaderField: "X-WP-TotalPages") == nil {
                break
            }
            page += 1
        }

        return deduplicatedWallpapers(wallpapers)
    }

    private func fetchAnimeCategoryID() async throws -> Int {
        let categoriesURL = makeWPURL(
            path: "wp/v2/categories",
            queryItems: [
                URLQueryItem(name: "slug", value: "anime"),
                URLQueryItem(name: "_fields", value: "id"),
            ]
        )
        let (data, _) = try await fetchData(from: categoriesURL)
        let categories = try JSONDecoder().decode([WordPressCategory].self, from: data)
        return categories.first?.id ?? 4
    }

    private func downloadCandidates(for sourcePageURL: URL) async throws -> [URL] {
        var candidates: [URL] = []

        if let slug = wallpaperSlug(from: sourcePageURL),
           let fromPost = try await fetchDownloadCandidatesFromWordPressPost(slug: slug) {
            candidates.append(contentsOf: fromPost)
        }

        let html = try await fetchText(from: sourcePageURL)
        candidates.append(contentsOf: playableURLs(in: html, relativeTo: sourcePageURL))

        return deduplicateURLs(expandPlayableCandidates(candidates))
            .sorted(by: { scorePlayableURL($0) > scorePlayableURL($1) })
    }

    private func fetchAnimeCatalogViaHTML() async throws -> [CatalogWallpaper] {
        let firstPageHTML = try await fetchText(from: animeListingURL)
        let totalPages = min(max(extractedTotalAnimePages(from: firstPageHTML), 1), 80)
        let paginationTemplates = extractAnimePaginationTemplates(from: firstPageHTML)
        var entries = extractAnimeListingEntries(from: firstPageHTML)

        if totalPages > 1 {
            for page in 2...totalPages {
                if let html = try await fetchAnimePageHTML(page: page, templates: paginationTemplates) {
                    let pageEntries = extractAnimeListingEntries(from: html)
                    for (postURL, previewURL) in pageEntries {
                        if let existing = entries[postURL] {
                            if existing == nil, let previewURL {
                                entries[postURL] = previewURL
                            }
                        } else {
                            entries[postURL] = previewURL
                        }
                    }
                }
            }
        }

        if entries.isEmpty {
            for postURL in extractAnimePostURLs(from: firstPageHTML) {
                entries[postURL] = nil
            }
        }

        let sortedURLs = entries.keys.sorted { lhs, rhs in
            lhs.absoluteString < rhs.absoluteString
        }
        let wallpapers = sortedURLs.map { postURL in
            let slug = wallpaperSlug(from: postURL) ?? UUID().uuidString
            return CatalogWallpaper(
                id: "waifu-\(slug)",
                title: titleFromSlug(slug),
                category: "Anime",
                attribution: "WallpaperWaifu",
                previewImageURL: entries[postURL] ?? nil,
                sourcePageURL: postURL,
                sources: []
            )
        }
        return deduplicatedWallpapers(wallpapers)
    }

    private func fetchDownloadCandidatesFromWordPressPost(slug: String) async throws -> [URL]? {
        let postURL = makeWPURL(
            path: "wp/v2/posts",
            queryItems: [
                URLQueryItem(name: "slug", value: slug),
                URLQueryItem(name: "_fields", value: "content"),
            ]
        )
        let (data, _) = try await fetchData(from: postURL)
        let posts = try JSONDecoder().decode([WordPressPostContent].self, from: data)
        guard let html = posts.first?.content.rendered else {
            return nil
        }
        return playableURLs(in: html, relativeTo: baseSiteURL)
    }

    private func fetchData(from url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("AuraFlow/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    private func fetchText(from url: URL) async throws -> String {
        let (data, _) = try await fetchData(from: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw URLError(.cannotDecodeRawData)
    }

    private func isPlayableURLReachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("AuraFlow/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            let status = httpResponse.statusCode
            guard (200...299).contains(status) || status == 206 else {
                return false
            }

            if let mime = httpResponse.mimeType?.lowercased() {
                if mime.hasPrefix("video/") || mime == "application/octet-stream" || mime == "binary/octet-stream" {
                    return true
                }
                if mime.hasPrefix("text/") {
                    return false
                }
            }

            let ext = url.pathExtension.lowercased()
            return ["mp4", "webm", "mov", "m4v"].contains(ext)
        } catch {
            return false
        }
    }

    private func makeWPURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseSiteURL, resolvingAgainstBaseURL: false)!
        components.path = "/wp-json/\(path)"
        components.queryItems = queryItems
        return components.url!
    }

    private func extractedTotalAnimePages(from html: String) -> Int {
        let matches = regexMatches(
            pattern: #"(?:/anime/page/|/category/anime/page/)(\d+)/"#,
            in: html
        )
        let pages = matches.compactMap { match -> Int? in
            guard match.count > 1 else { return nil }
            return Int(match[1])
        }
        return pages.max() ?? 1
    }

    private func extractAnimePaginationTemplates(from html: String) -> [String] {
        let matches = regexMatches(
            pattern: #"href=["']([^"']*(?:/anime/page/|/category/anime/page/)\d+/)["']"#,
            in: html
        )
        var templates: [String] = []
        var seen = Set<String>()
        for match in matches {
            guard match.count > 1 else { continue }
            let href = match[1]
            let template = href.replacingOccurrences(
                of: #"(?:/anime/page/|/category/anime/page/)\d+/"#,
                with: "{{PAGE}}",
                options: .regularExpression
            )
            guard !template.isEmpty else { continue }
            if seen.insert(template).inserted {
                templates.append(template)
            }
        }
        return templates
    }

    private func fetchAnimePageHTML(page: Int, templates: [String]) async throws -> String? {
        var candidateTemplates = templates
        if candidateTemplates.isEmpty {
            candidateTemplates = [
                "/anime/page/{{PAGE}}/",
                "/category/anime/page/{{PAGE}}/",
                "https://wallpaperwaifu.com/anime/page/{{PAGE}}/",
                "https://wallpaperwaifu.com/category/anime/page/{{PAGE}}/",
            ]
        }

        for template in candidateTemplates {
            let link = template.replacingOccurrences(of: "{{PAGE}}", with: String(page))
            guard let url = normalizedURL(from: link, relativeTo: baseSiteURL) else {
                continue
            }
            do {
                return try await fetchText(from: url)
            } catch {
                continue
            }
        }
        return nil
    }

    private func extractAnimeListingEntries(from html: String) -> [URL: URL?] {
        let matches = regexMatches(
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<img[^>]+(?:data-src|data-lazy-src|data-original|src)=["']([^"']+)["']"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        var entries: [URL: URL?] = [:]
        for match in matches {
            guard match.count > 2 else { continue }
            guard let postURL = normalizedURL(from: match[1], relativeTo: baseSiteURL) else { continue }
            let path = postURL.path.lowercased()
            guard path.hasPrefix("/anime/") else { continue }
            if path.contains("/page/") || path.hasSuffix("/anime/") {
                continue
            }
            let previewURL = normalizedAssetURL(from: match[2], relativeTo: baseSiteURL)
            if let existing = entries[postURL] {
                if existing == nil, let previewURL {
                    entries[postURL] = previewURL
                }
            } else {
                entries[postURL] = previewURL
            }
        }
        return entries
    }

    private func extractAnimePostURLs(from html: String) -> Set<URL> {
        let matches = regexMatches(
            pattern: #"href=["']([^"']+)["']"#,
            in: html
        )
        var urls: Set<URL> = []
        for match in matches {
            guard match.count > 1 else { continue }
            guard let url = normalizedURL(from: match[1], relativeTo: baseSiteURL) else { continue }
            let path = url.path.lowercased()
            guard path.hasPrefix("/anime/") else { continue }
            if path.contains("/page/") || path.hasSuffix("/anime/") {
                continue
            }
            urls.insert(url)
        }
        return urls
    }

    private func playableURLs(in raw: String, relativeTo base: URL) -> [URL] {
        let normalized = decodeHTMLEntities(raw.replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression))
        var candidates: [URL] = []

        let absoluteMatches = regexMatches(
            pattern: #"https?://[^"'<>\s]+?\.(?:mp4|webm|mov|m4v)(?:\?[^"'<>\s]*)?"#,
            in: normalized
        )
        for match in absoluteMatches {
            guard let value = match.first, let url = URL(string: value) else { continue }
            candidates.append(url)
        }

        let relativeMatches = regexMatches(
            pattern: #"/wp-content/uploads/[^"'<>\s]+?\.(?:mp4|webm|mov|m4v)(?:\?[^"'<>\s]*)?"#,
            in: normalized
        )
        for match in relativeMatches {
            guard let value = match.first,
                  let resolved = URL(string: value, relativeTo: base)?.absoluteURL else {
                continue
            }
            candidates.append(resolved)
        }
        return deduplicateURLs(candidates).sorted(by: { scorePlayableURL($0) > scorePlayableURL($1) })
    }

    private func expandPlayableCandidates(_ candidates: [URL]) -> [URL] {
        var expanded = candidates
        expanded.reserveCapacity(candidates.count * 2)

        for url in candidates {
            let ext = url.pathExtension.lowercased()
            if ext == "webm", let alt = replacingPathExtension(of: url, with: "mp4") {
                expanded.append(alt)
            } else if ext == "mp4", let alt = replacingPathExtension(of: url, with: "webm") {
                expanded.append(alt)
            }
        }
        return expanded
    }

    private func replacingPathExtension(of url: URL, with newExtension: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        guard let dotIndex = path.lastIndex(of: ".") else {
            return nil
        }
        let prefix = path[..<dotIndex]
        components?.percentEncodedPath = "\(prefix).\(newExtension)"
        return components?.url
    }

    private func scorePlayableURL(_ url: URL) -> Int {
        var score = 0
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host.contains("wallpaperwaifu.com") {
            score += 100
        }
        if path.contains("/wp-content/uploads/") {
            score += 30
        }
        if path.contains("-thumb-") {
            score -= 50
        }
        switch url.pathExtension.lowercased() {
        case "mp4":
            score += 20
        case "webm":
            score += 15
        case "mov", "m4v":
            score += 10
        default:
            break
        }
        return score
    }

    private func wallpaperSlug(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let slug = parts.last else {
            return nil
        }
        return slug.lowercased()
    }

    private func titleFromSlug(_ slug: String) -> String {
        let cleaned = slug
            .replacingOccurrences(of: "-live-wallpaper", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Anime Wallpaper"
        }
        return cleaned
            .split(separator: " ")
            .map { word in
                let value = String(word)
                guard let first = value.first else { return value }
                return first.uppercased() + value.dropFirst()
            }
            .joined(separator: " ")
    }

    private func normalizedTitle(_ raw: String, fallback: String) -> String {
        let noTags = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? fallback : decoded
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func deduplicatedWallpapers(_ wallpapers: [CatalogWallpaper]) -> [CatalogWallpaper] {
        var seen = Set<String>()
        var unique: [CatalogWallpaper] = []
        unique.reserveCapacity(wallpapers.count)
        for wallpaper in wallpapers {
            if seen.insert(wallpaper.id).inserted {
                unique.append(wallpaper)
            }
        }
        return unique
    }

    private func regexMatches(
        pattern: String,
        in input: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, options: [], range: range).map { result in
            (0..<result.numberOfRanges).compactMap { index in
                let range = result.range(at: index)
                guard range.location != NSNotFound,
                      let swiftRange = Range(range, in: input) else {
                    return nil
                }
                return String(input[swiftRange])
            }
        }
    }

    private func deduplicateURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        result.reserveCapacity(urls.count)
        for url in urls {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    private func normalizedURL(from raw: String, relativeTo base: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("javascript:") || trimmed.hasPrefix("#") {
            return nil
        }
        if let absolute = URL(string: trimmed), let host = absolute.host?.lowercased() {
            if host.contains("wallpaperwaifu.com") {
                return absolute
            }
        }
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: base)?.absoluteURL
        }
        return nil
    }

    private func normalizedAssetURL(from raw: String, relativeTo base: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("javascript:") || trimmed.hasPrefix("#") {
            return nil
        }
        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: base)?.absoluteURL
        }
        return nil
    }

    private func persistCatalog(_ wallpapers: [CatalogWallpaper]) throws {
        let envelope = CatalogCacheEnvelope(updatedAt: Date(), wallpapers: wallpapers)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: try catalogCacheURL(), options: .atomic)
    }

    private func loadDownloadURLCacheIfNeeded() throws {
        if didLoadDownloadURLCache {
            return
        }
        didLoadDownloadURLCache = true
        let cacheURL = try downloadCacheURL()
        guard let data = try? Data(contentsOf: cacheURL) else {
            downloadURLCache = [:]
            return
        }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            downloadURLCache = [:]
            return
        }
        downloadURLCache = decoded.reduce(into: [:]) { partial, pair in
            if let url = URL(string: pair.value) {
                partial[pair.key] = url
            }
        }
    }

    private func persistDownloadURLCache() throws {
        let payload = downloadURLCache.reduce(into: [String: String]()) { partial, pair in
            partial[pair.key] = pair.value.absoluteString
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: try downloadCacheURL(), options: .atomic)
    }

    private func catalogCacheURL() throws -> URL {
        try catalogSupportDirectory().appendingPathComponent("waifu-anime-cache.json")
    }

    private func downloadCacheURL() throws -> URL {
        try catalogSupportDirectory().appendingPathComponent("waifu-download-links.json")
    }

    private func catalogSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("AuraFlow", isDirectory: true)
            .appendingPathComponent("Catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct CatalogCacheEnvelope: Codable {
    let updatedAt: Date
    let wallpapers: [CatalogWallpaper]
}

private struct WordPressCategory: Decodable {
    let id: Int
}

private struct WordPressPostSummary: Decodable {
    struct RenderedText: Decodable {
        let rendered: String
    }

    struct Embedded: Decodable {
        struct FeaturedMedia: Decodable {
            let sourceURL: String?

            enum CodingKeys: String, CodingKey {
                case sourceURL = "source_url"
            }
        }

        let featuredMedia: [FeaturedMedia]?

        enum CodingKeys: String, CodingKey {
            case featuredMedia = "wp:featuredmedia"
        }
    }

    let id: Int
    let slug: String
    let link: String
    let title: RenderedText
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case link
        case title
        case embedded = "_embedded"
    }
}

private struct WordPressPostContent: Decodable {
    struct RenderedText: Decodable {
        let rendered: String
    }

    let content: RenderedText
}
