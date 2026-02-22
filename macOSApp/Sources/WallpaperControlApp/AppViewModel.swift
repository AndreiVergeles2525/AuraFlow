import AppKit
import AVKit
import Combine
import Foundation
import PythonBridgeKit
import UniformTypeIdentifiers

struct ControlConfig: Codable {
    var video_path: String
    var playback_speed: Double
    var volume: Double?
    var autostart: Bool?
}

struct ControlStatus: Codable {
    var running: Bool
    var config: ControlConfig
    var pid: Int?
    var autostart: Bool?
    var paused: Bool? = nil
    var wallpaper_restored: Bool? = nil
}

struct CatalogVideoSource: Hashable {
    let url: URL
    let width: Int
    let height: Int
}

struct CatalogWallpaper: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let attribution: String
    let previewImageURL: URL?
    let sourcePageURL: URL?
    let sources: [CatalogVideoSource]

    static let defaultCatalog: [CatalogWallpaper] = [
        CatalogWallpaper(
            id: "anime-sky-city",
            title: "Anime Sky City",
            category: "Anime",
            attribution: "Mixkit",
            previewImageURL: URL(string: "https://assets.mixkit.co/videos/39767/39767-thumb-360-0.jpg"),
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/39767/39767-720.mp4")!, width: 1280, height: 720)
            ]
        ),
        CatalogWallpaper(
            id: "anime-neon-street",
            title: "Neon Street Drift",
            category: "Anime",
            attribution: "Mixkit",
            previewImageURL: URL(string: "https://assets.mixkit.co/videos/34487/34487-thumb-360-0.jpg"),
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/34487/34487-720.mp4")!, width: 1280, height: 720)
            ]
        ),
        CatalogWallpaper(
            id: "anime-cloud-night",
            title: "Dreamy Cloud Night",
            category: "Anime",
            attribution: "Mixkit",
            previewImageURL: URL(string: "https://assets.mixkit.co/videos/34404/34404-thumb-360-0.jpg"),
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/34404/34404-720.mp4")!, width: 1280, height: 720)
            ]
        ),
        CatalogWallpaper(
            id: "yellow-flowers-tree",
            title: "Yellow Flower Tree",
            category: "Nature",
            attribution: "Mixkit",
            previewImageURL: nil,
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/preview/mixkit-tree-with-yellow-flowers-1173-large.mp4")!, width: 1920, height: 1080)
            ]
        ),
        CatalogWallpaper(
            id: "beach-walk",
            title: "Beach Walk",
            category: "Nature",
            attribution: "Mixkit",
            previewImageURL: nil,
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/preview/mixkit-woman-walking-on-the-beach-1111-large.mp4")!, width: 1920, height: 1080)
            ]
        ),
        CatalogWallpaper(
            id: "space-stars",
            title: "Stars in Space",
            category: "Space",
            attribution: "Mixkit",
            previewImageURL: nil,
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/preview/mixkit-stars-in-space-1610-large.mp4")!, width: 1920, height: 1080)
            ]
        ),
        CatalogWallpaper(
            id: "night-phone",
            title: "Night Lights",
            category: "Urban",
            attribution: "Mixkit",
            previewImageURL: nil,
            sourcePageURL: URL(string: "https://mixkit.co"),
            sources: [
                CatalogVideoSource(url: URL(string: "https://assets.mixkit.co/videos/preview/mixkit-woman-at-night-lying-down-using-her-cell-phone-43381-large.mp4")!, width: 1920, height: 1080)
            ]
        )
    ]
}

protocol PythonControlling {
    func status() throws -> ControlStatus
    func start(videoURL: URL?, speed: Double?) throws -> ControlStatus
    func stop() throws -> ControlStatus
    func clearWallpaper() throws -> ControlStatus
    func setVideo(_ url: URL) throws -> ControlStatus
    func setSpeed(_ speed: Double) throws -> ControlStatus
    func setAutostart(_ enabled: Bool) throws -> ControlStatus
}

enum PythonControllerError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

final class PythonController: PythonControlling {
    private let bridge: PythonBridge

    init() throws {
        guard let bridge = PythonBridge(bundleResource: "control") else {
            let message = PythonBridge.lastError?.localizedDescription ?? "Python bridge unavailable. Ensure Python 3 with PyObjC is installed."
            throw PythonControllerError.unavailable(message)
        }
        self.bridge = bridge
    }

    private func run(command: String, arguments: [String] = []) throws -> ControlStatus {
        do {
            let output = try bridge.runCommand(command, arguments: arguments)
            let data = Data(output.utf8)
            return try JSONDecoder().decode(ControlStatus.self, from: data)
        } catch {
            throw PythonControllerError.unavailable(error.localizedDescription)
        }
    }

    func status() throws -> ControlStatus {
        try run(command: "status")
    }

    func start(videoURL: URL?, speed: Double?) throws -> ControlStatus {
        var args: [String] = []
        if let videoURL {
            args.append(contentsOf: ["--video", videoURL.path])
        }
        if let speed {
            args.append(contentsOf: ["--speed", String(speed)])
        }
        return try run(command: "start", arguments: args)
    }

    func stop() throws -> ControlStatus {
        try run(command: "stop")
    }

    func clearWallpaper() throws -> ControlStatus {
        try run(command: "clear-wallpaper")
    }

    func setVideo(_ url: URL) throws -> ControlStatus {
        try run(command: "set-video", arguments: [url.path])
    }

    func setSpeed(_ speed: Double) throws -> ControlStatus {
        try run(command: "set-speed", arguments: [String(speed)])
    }

    func setAutostart(_ enabled: Bool) throws -> ControlStatus {
        let state = enabled ? "on" : "off"
        return try run(command: "set-autostart", arguments: [state])
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var videoURL: URL?
    @Published var playbackSpeed: Double = 1.0
    @Published var isRunning: Bool = false
    @Published var autostartEnabled: Bool = false
    @Published var isBusy: Bool = false
    @Published var statusMessage: String?
    @Published var alertMessage: String?
    @Published var previewPlayer: AVPlayer?
    @Published var isCatalogOpen: Bool = false
    @Published var selectedCatalogWallpaper: CatalogWallpaper?
    @Published var catalogSearchText: String = ""
    @Published var catalogDownloadID: String?

    let catalogWallpapers: [CatalogWallpaper] = CatalogWallpaper.defaultCatalog

    private let controller: PythonControlling?
    private var previewEndObserver: NSObjectProtocol?
    private var didAttemptAutostartOnLaunch = false
    private var healthMonitorTask: Task<Void, Never>?
    private var isHealthCheckInProgress = false

    var isControllerAvailable: Bool {
        controller != nil
    }

    var selectedVideoName: String {
        videoURL?.lastPathComponent ?? "Not selected"
    }

    var canStart: Bool {
        isControllerAvailable && !isBusy && !isRunning && videoURL != nil
    }

    var canStop: Bool {
        isControllerAvailable && !isBusy && isRunning
    }

    var canClearWallpaper: Bool {
        isControllerAvailable && !isBusy
    }

    var canToggleAutostart: Bool {
        isControllerAvailable && !isBusy
    }

    var canApplyCatalogWallpaper: Bool {
        isControllerAvailable && !isBusy && catalogDownloadID == nil
    }

    var filteredCatalogWallpapers: [CatalogWallpaper] {
        let query = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalogWallpapers }
        return catalogWallpapers.filter { wallpaper in
            wallpaper.title.localizedCaseInsensitiveContains(query)
                || wallpaper.category.localizedCaseInsensitiveContains(query)
        }
    }

    init(controller: PythonControlling? = nil) {
        if let controller {
            self.controller = controller
        } else {
            do {
                self.controller = try PythonController()
            } catch {
                self.controller = nil
                alertMessage = error.localizedDescription
            }
        }
        startHealthMonitor()
    }

    deinit {
        healthMonitorTask?.cancel()
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
        }
    }

    func loadStatus() async {
        guard let controller else {
            alertMessage = "Python bridge unavailable."
            return
        }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await runAsync { try controller.status() }
            apply(status: status)
            await startFromAutostartIfNeeded(using: status)
            alertMessage = nil
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func chooseVideo(force: Bool = false) {
        guard force || !isBusy else { return }
        let panel = NSOpenPanel()
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            videoURL = url
            configurePreview(for: url)
            Task {
                await applyVideoSelection(url)
            }
        }
    }

    func chooseVideoFromMenuBar() {
        Task { @MainActor in
            var retries = 0
            while isBusy && retries < 20 {
                retries += 1
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            chooseVideo(force: true)
        }
    }

    func openCatalog() {
        isCatalogOpen = true
    }

    func openCatalogFromMenuBar() {
        isCatalogOpen = true
    }

    func openCatalogWallpaper(_ wallpaper: CatalogWallpaper) {
        selectedCatalogWallpaper = wallpaper
    }

    func navigateBackFromCatalog() {
        if selectedCatalogWallpaper != nil {
            selectedCatalogWallpaper = nil
            return
        }
        isCatalogOpen = false
    }

    func isDownloading(_ wallpaper: CatalogWallpaper) -> Bool {
        catalogDownloadID == wallpaper.id
    }

    func applyCatalogWallpaper(_ wallpaper: CatalogWallpaper) {
        guard canApplyCatalogWallpaper else { return }
        catalogDownloadID = wallpaper.id

        Task {
            defer { catalogDownloadID = nil }
            do {
                let localURL = try await downloadCatalogVideo(for: wallpaper)
                await applyVideoSelection(localURL)
                statusMessage = "Catalog wallpaper applied."
                alertMessage = nil
            } catch {
                alertMessage = "Failed to download wallpaper: \(error.localizedDescription)"
            }
        }
    }

    func applyVideoSelection(_ url: URL) async {
        guard let controller else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await runAsync { try controller.setVideo(url) }
            apply(status: status)
            statusMessage = "Wallpaper source updated."
            alertMessage = nil
        } catch {
            alertMessage = "Failed to set video: \(error.localizedDescription)"
        }
    }

    func start() {
        guard let controller else { return }
        guard !isBusy else { return }
        guard videoURL != nil else {
            alertMessage = "Choose a video before starting."
            return
        }

        Task { [controller] in
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync {
                    try controller.start(videoURL: nil, speed: nil)
                }
                apply(status: status)
                statusMessage = "Wallpaper started."
                alertMessage = nil
            } catch {
                alertMessage = "Failed to start: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard let controller else { return }
        guard !isBusy else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.stop() }
                apply(status: status)
                statusMessage = "Paused on current frame."
                alertMessage = nil
            } catch {
                alertMessage = "Failed to pause: \(error.localizedDescription)"
            }
        }
    }

    func clearWallpaper() {
        guard let controller else { return }
        guard !isBusy else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.clearWallpaper() }
                apply(status: status)
                if status.wallpaper_restored == false {
                    statusMessage = "Wallpaper backup not found."
                } else {
                    statusMessage = "Original wallpaper restored."
                }
                alertMessage = nil
            } catch {
                alertMessage = "Failed to restore wallpaper: \(error.localizedDescription)"
            }
        }
    }

    func updateSpeed(_ speed: Double) {
        playbackSpeed = speed
        guard let controller else { return }
        guard !isBusy else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setSpeed(speed) }
                apply(status: status)
                statusMessage = "Speed updated."
                alertMessage = nil
            } catch {
                alertMessage = "Failed to update speed: \(error.localizedDescription)"
            }
        }
    }

    func toggleAutostart(_ enabled: Bool) {
        guard !isBusy else {
            autostartEnabled = !enabled
            return
        }
        if enabled && videoURL == nil {
            autostartEnabled = false
            alertMessage = "Choose a video before enabling launch at login."
            return
        }

        let previous = autostartEnabled
        autostartEnabled = enabled
        guard let controller else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setAutostart(enabled) }
                apply(status: status)
                statusMessage = enabled ? "Launch at login enabled." : "Launch at login disabled."
                alertMessage = nil
            } catch {
                autostartEnabled = previous
                alertMessage = "Failed to update launch at login: \(error.localizedDescription)"
            }
        }
    }

    func preview() {
        configurePreview(for: videoURL)
    }

    private func apply(status: ControlStatus, refreshPreview: Bool = true) {
        isRunning = status.running
        playbackSpeed = status.config.playback_speed
        autostartEnabled = status.autostart ?? status.config.autostart ?? false
        if !status.config.video_path.isEmpty {
            let currentURL = URL(fileURLWithPath: status.config.video_path)
            let hasVideoChanged = videoURL?.path != currentURL.path
            videoURL = currentURL
            if refreshPreview && (hasVideoChanged || previewPlayer == nil) {
                configurePreview(for: currentURL)
            }
        } else {
            videoURL = nil
            previewPlayer = nil
        }
    }

    private func startHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await self?.recoverPlaybackIfUnexpectedlyStopped()
            }
        }
    }

    private func recoverPlaybackIfUnexpectedlyStopped() async {
        guard let controller else { return }
        guard !isBusy else { return }
        guard !isHealthCheckInProgress else { return }

        isHealthCheckInProgress = true
        defer { isHealthCheckInProgress = false }

        do {
            let status = try await runAsync { try controller.status() }
            let hasVideo = !status.config.video_path.isEmpty
            let paused = status.paused ?? false
            let shouldRecover = isRunning && !status.running && !paused && hasVideo

            if shouldRecover {
                let recoveredStatus = try await runAsync {
                    try controller.start(videoURL: nil, speed: nil)
                }
                apply(status: recoveredStatus, refreshPreview: false)
                statusMessage = "Playback recovered after interruption."
                alertMessage = nil
            } else {
                apply(status: status, refreshPreview: false)
            }
        } catch {
            // Ignore background health check errors to avoid noisy alerts.
        }
    }

    private func downloadCatalogVideo(for wallpaper: CatalogWallpaper) async throws -> URL {
        guard let source = preferredSource(for: wallpaper) else {
            throw URLError(.badURL)
        }

        let destination = try catalogDirectoryURL().appendingPathComponent(
            "\(wallpaper.id)-\(source.width)x\(source.height).mp4"
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: source.url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func preferredSource(for wallpaper: CatalogWallpaper) -> CatalogVideoSource? {
        guard !wallpaper.sources.isEmpty else { return nil }
        guard wallpaper.sources.count > 1 else { return wallpaper.sources.first }

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let targetWidth = Int(screenFrame.width)
        let targetHeight = Int(screenFrame.height)

        let largerOrEqual = wallpaper.sources.filter { source in
            source.width >= targetWidth && source.height >= targetHeight
        }

        if let best = largerOrEqual.min(by: { lhs, rhs in
            (lhs.width * lhs.height) < (rhs.width * rhs.height)
        }) {
            return best
        }

        return wallpaper.sources.max(by: { lhs, rhs in
            (lhs.width * lhs.height) < (rhs.width * rhs.height)
        })
    }

    private func catalogDirectoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("AuraFlow", isDirectory: true)
            .appendingPathComponent("Catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func configurePreview(for url: URL?) {
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }

        guard let url else {
            previewPlayer = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.play()

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        previewPlayer = player
    }

    private func startFromAutostartIfNeeded(using status: ControlStatus) async {
        guard let controller else { return }
        guard !didAttemptAutostartOnLaunch else { return }
        didAttemptAutostartOnLaunch = true

        let autostart = status.autostart ?? status.config.autostart ?? false
        guard autostart else { return }
        guard !status.running else { return }
        guard !status.config.video_path.isEmpty else { return }

        do {
            let updatedStatus = try await runAsync {
                try controller.start(videoURL: nil, speed: nil)
            }
            apply(status: updatedStatus)
            statusMessage = "Launch at login: wallpaper started."
            alertMessage = nil
        } catch {
            alertMessage = "Launch at login error: \(error.localizedDescription)"
        }
    }

    private func runAsync<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
