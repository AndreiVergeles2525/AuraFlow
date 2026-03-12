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
    var blend_interpolation: Bool? = nil
    var pause_on_fullscreen: Bool? = nil
    var scale_mode: String? = nil
}

struct ControlStatus: Codable {
    var contract_version: Int? = nil
    var running: Bool
    var config: ControlConfig
    var pid: Int?
    var autostart: Bool?
    var paused: Bool? = nil
    var wallpaper_restored: Bool? = nil
    var wallpaper: String? = nil
    var health: DaemonHealth? = nil
}

struct DaemonHealth: Codable {
    var contract_version: Int? = nil
    var available: Bool? = nil
    var fresh: Bool? = nil
    var suspicious: Bool? = nil
    var reason: String? = nil
    var updated_at: Double? = nil
    var lag_seconds: Double? = nil
    var screens: Int? = nil
    var windows: Int? = nil
    var player_rate: Double? = nil
    var stall_events: Int? = nil
    var recovery_events: Int? = nil
    var consecutive_stall_polls: Int? = nil
    var paused: Bool? = nil
    var manual_paused: Bool? = nil
    var low_power_mode: Bool? = nil
    var auto_paused_for_low_power: Bool? = nil
    var pause_on_fullscreen: Bool? = nil
    var fullscreen_app_detected: Bool? = nil
    var auto_paused_for_fullscreen: Bool? = nil
    var blend_interpolation_enabled: Bool? = nil
    var blend_interpolation_active: Bool? = nil
    var scale_mode: String? = nil
}

enum WallpaperScaleMode: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill:
            return "Fill"
        case .fit:
            return "Fit"
        case .stretch:
            return "Stretch"
        }
    }

    var commandValue: String { rawValue }

    var previewGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            return .resizeAspectFill
        case .fit:
            return .resizeAspect
        case .stretch:
            return .resize
        }
    }
}

struct DaemonMetrics: Codable {
    var contract_version: Int? = nil
    var updated_at: Double? = nil
    var running: Bool
    var paused: Bool? = nil
    var pid: Int? = nil
    var daemon_pids: [Int]? = nil
    var process_count: Int? = nil
    var cpu_percent: Double? = nil
    var memory_mb: Double? = nil
    var thread_count: Int? = nil
    var health: DaemonHealth? = nil
}

struct CatalogVideoSource: Hashable, Codable {
    let url: URL
    let width: Int
    let height: Int
}

struct CatalogWallpaper: Identifiable, Hashable, Codable {
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

struct DownloadedCatalogWallpaper: Identifiable, Hashable, Codable {
    let id: String
    let wallpaperID: String
    let title: String
    let category: String
    let attribution: String
    let previewImageURL: URL?
    let sourcePageURL: URL?
    let localPath: String
    let downloadedAt: Date

    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }
}

protocol PythonControlling {
    func status() throws -> ControlStatus
    func start(videoURL: URL?, speed: Double?) throws -> ControlStatus
    func stop() throws -> ControlStatus
    func clearWallpaper() throws -> ControlStatus
    func setVideo(_ url: URL) throws -> ControlStatus
    func setSpeed(_ speed: Double) throws -> ControlStatus
    func setInterpolation(_ enabled: Bool) throws -> ControlStatus
    func setPauseOnFullscreen(_ enabled: Bool) throws -> ControlStatus
    func setScaleMode(_ mode: WallpaperScaleMode) throws -> ControlStatus
    func setAutostart(_ enabled: Bool) throws -> ControlStatus
    func metrics() throws -> DaemonMetrics
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

    private func runMetrics(command: String, arguments: [String] = []) throws -> DaemonMetrics {
        do {
            let output = try bridge.runCommand(command, arguments: arguments)
            let data = Data(output.utf8)
            return try JSONDecoder().decode(DaemonMetrics.self, from: data)
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

    func setInterpolation(_ enabled: Bool) throws -> ControlStatus {
        let state = enabled ? "on" : "off"
        return try run(command: "set-interpolation", arguments: [state])
    }

    func setPauseOnFullscreen(_ enabled: Bool) throws -> ControlStatus {
        let state = enabled ? "on" : "off"
        return try run(command: "set-fullscreen-pause", arguments: [state])
    }

    func setScaleMode(_ mode: WallpaperScaleMode) throws -> ControlStatus {
        try run(command: "set-scale", arguments: [mode.commandValue])
    }

    func setAutostart(_ enabled: Bool) throws -> ControlStatus {
        let state = enabled ? "on" : "off"
        return try run(command: "set-autostart", arguments: [state])
    }

    func metrics() throws -> DaemonMetrics {
        try runMetrics(command: "metrics")
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var videoURL: URL?
    @Published var playbackSpeed: Double = 1.0
    @Published var isRunning: Bool = false
    @Published var autostartEnabled: Bool = false
    @Published var blendInterpolationEnabled: Bool = false
    @Published var pauseOnFullscreenEnabled: Bool = true
    @Published var scaleMode: WallpaperScaleMode = .fill
    @Published var isSettingsOpen: Bool = false
    @Published var isMonitoringOpen: Bool = false
    @Published var monitoringSnapshot: DaemonMetrics?
    @Published var monitoringErrorMessage: String?
    @Published var isMonitoringRefreshing: Bool = false
    @Published var optimizationEnabled: Bool = true
    @Published var optimizationAllowAV1Passthrough: Bool = true
    @Published var optimizationTranscodeH264ToHEVC: Bool = true
    @Published var optimizationForceSoftwareAV1Encode: Bool = false
    @Published private(set) var optimizationHardwareAV1DecodeAvailable: Bool = false
    @Published var optimizationProfile: OptimizationProfile = .balanced
    @Published var optimizationInProgress: Bool = false
    @Published var optimizationProgress: Double = 0.0
    @Published var optimizationLabel: String?
    @Published var isBusy: Bool = false
    @Published var statusMessage: String?
    @Published var alertMessage: String?
    @Published var previewPlayer: AVPlayer?
    @Published var isCatalogOpen: Bool = false
    @Published var isDownloadedWallpapersOpen: Bool = false
    @Published var selectedCatalogWallpaper: CatalogWallpaper?
    @Published var catalogSearchText: String = ""
    @Published var catalogDownloadID: String?
    @Published private(set) var catalogWallpapers: [CatalogWallpaper] = CatalogWallpaper.defaultCatalog
    @Published private(set) var catalogIsRefreshing: Bool = false
    @Published private(set) var downloadedCatalogWallpapers: [DownloadedCatalogWallpaper] = []

    private let controller: PythonControlling?
    private let catalogProvider: WallpaperCatalogProviding
    private let optimizer = VideoOptimizer()
    private let optimizationStore: VideoOptimizationStore
    private var previewEndObserver: NSObjectProtocol?
    private var didAttemptAutostartOnLaunch = false
    private var healthMonitorTask: Task<Void, Never>?
    private var isHealthCheckInProgress = false
    private var bridgeFailureCount = 0
    private var daemonSuspiciousPolls = 0
    private var lowPowerAutoPauseActive = false
    private var fullscreenAutoPauseActive = false
    private var monitoringTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var isShuttingDown = false
    private var catalogNavigationLockedUntil: Date = .distantPast
    private var catalogRefreshTask: Task<Void, Never>?
    private var lastCatalogRefreshAt: Date?

    private let expectedStatusContractVersion = 2
    private let bridgeFailureThreshold = 3
    private let daemonSuspiciousThreshold = 2

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

    var canToggleBlendInterpolation: Bool {
        isControllerAvailable && !isBusy
    }

    var canTogglePauseOnFullscreen: Bool {
        isControllerAvailable && !isBusy
    }

    var canToggleScaleMode: Bool {
        isControllerAvailable && !isBusy
    }

    var canOpenMonitoring: Bool {
        isControllerAvailable
    }

    var canChangeOptimizationSettings: Bool {
        !isBusy && !optimizationInProgress
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

    init(
        controller: PythonControlling? = nil,
        optimizationStore: VideoOptimizationStore = VideoOptimizationStore(),
        catalogProvider: WallpaperCatalogProviding = WallpaperWaifuCatalogProvider()
    ) {
        self.optimizationStore = optimizationStore
        self.catalogProvider = catalogProvider
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
        optimizationHardwareAV1DecodeAvailable = optimizer.supportsHardwareAV1Decode()
        applyOptimizationSettings(optimizationStore.load())
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.beginShutdown()
            }
        }
        Task { [weak self] in
            await self?.loadCatalogFromCache()
            await MainActor.run {
                self?.loadDownloadedCatalogWallpapers()
            }
        }
        startHealthMonitor()
    }

    deinit {
        healthMonitorTask?.cancel()
        monitoringTask?.cancel()
        catalogRefreshTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
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
            let needsNormalizationURL = configuredVideoNeedingCompatibilityNormalization(from: status)
            recordBridgeSuccess()
            await startFromAutostartIfNeeded(using: status)
            if let needsNormalizationURL {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await self?.applyVideoSelection(
                        needsNormalizationURL,
                        surfaceErrors: false
                    )
                }
            }
            alertMessage = nil
        } catch {
            recordBridgeFailure(error, context: "status")
        }
    }

    func chooseVideo(force: Bool = false) {
        guard force || !isBusy else { return }
        let panel = NSOpenPanel()
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie, .gif]
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
        isSettingsOpen = false
        closeMonitoring()
        closeDownloadedWallpapers()
        selectedCatalogWallpaper = nil
        isCatalogOpen = true
        refreshCatalogIfNeeded()
    }

    func openCatalogFromMenuBar() {
        isSettingsOpen = false
        closeMonitoring()
        closeDownloadedWallpapers()
        selectedCatalogWallpaper = nil
        isCatalogOpen = true
        refreshCatalogIfNeeded()
    }

    func openDownloadedWallpapers() {
        isCatalogOpen = false
        selectedCatalogWallpaper = nil
        closeSettings()
        closeMonitoring()
        loadDownloadedCatalogWallpapers()
        isDownloadedWallpapersOpen = true
    }

    func closeDownloadedWallpapers() {
        isDownloadedWallpapersOpen = false
    }

    func applyDownloadedCatalogWallpaper(_ wallpaper: DownloadedCatalogWallpaper) {
        let localURL = wallpaper.localURL
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            loadDownloadedCatalogWallpapers()
            alertMessage = "Downloaded wallpaper file is missing. Re-download from catalog."
            return
        }

        closeDownloadedWallpapers()
        Task {
            let previousPath = videoURL?.standardizedFileURL.path
            await applyVideoSelection(localURL)
            syncDownloadedCatalogWallpaperAfterApply(
                wallpaperID: wallpaper.wallpaperID,
                requestedURL: localURL,
                previousVideoPath: previousPath
            )
        }
    }

    func openCatalogWallpaper(_ wallpaper: CatalogWallpaper) {
        guard Date() >= catalogNavigationLockedUntil else { return }
        selectedCatalogWallpaper = wallpaper
    }

    func navigateBackFromCatalog() {
        if selectedCatalogWallpaper != nil {
            selectedCatalogWallpaper = nil
            catalogNavigationLockedUntil = Date().addingTimeInterval(0.35)
            return
        }
        selectedCatalogWallpaper = nil
        isCatalogOpen = false
        catalogNavigationLockedUntil = Date().addingTimeInterval(0.2)
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
                registerDownloadedCatalogWallpaper(for: wallpaper, localURL: localURL)
                let previousPath = videoURL?.standardizedFileURL.path
                await applyVideoSelection(localURL)
                syncDownloadedCatalogWallpaperAfterApply(
                    wallpaperID: wallpaper.id,
                    requestedURL: localURL,
                    previousVideoPath: previousPath
                )
                alertMessage = nil
            } catch {
                alertMessage = "Failed to download wallpaper: \(error.localizedDescription)"
            }
        }
    }

    func applyVideoSelection(_ url: URL, surfaceErrors: Bool = true) async {
        guard let controller else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let prepared = try await prepareVideoURLForPlayback(url)
            let status = try await runAsync { try controller.setVideo(prepared.url) }
            apply(status: status)
            recordBridgeSuccess()
            statusMessage = prepared.summary ?? "Wallpaper source updated."
            alertMessage = nil
        } catch {
            recordBridgeFailure(error, context: "set-video", surface: surfaceErrors)
            if surfaceErrors && bridgeFailureCount < bridgeFailureThreshold {
                alertMessage = "Failed to set video: \(error.localizedDescription)"
            }
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
                recordBridgeSuccess()
                statusMessage = "Wallpaper started."
                alertMessage = nil
            } catch {
                recordBridgeFailure(error, context: "start")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to start: \(error.localizedDescription)"
                }
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
                recordBridgeSuccess()
                statusMessage = "Paused on current frame."
                alertMessage = nil
            } catch {
                recordBridgeFailure(error, context: "pause")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to pause: \(error.localizedDescription)"
                }
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
                let restored = status.wallpaper_restored ?? false
                recordBridgeSuccess()
                if restored {
                    statusMessage = "Original wallpaper restored."
                } else {
                    statusMessage = "Wallpaper backup not found."
                }
                alertMessage = nil
            } catch {
                recordBridgeFailure(error, context: "clear-wallpaper")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to restore wallpaper: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateSpeed(_ speed: Double) {
        setPreviewPlaybackSpeed(speed)
        guard let controller else { return }
        guard !isBusy else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setSpeed(speed) }
                apply(status: status)
                recordBridgeSuccess()
                statusMessage = "Speed updated."
                alertMessage = nil
            } catch {
                recordBridgeFailure(error, context: "set-speed")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to update speed: \(error.localizedDescription)"
                }
            }
        }
    }

    func setPreviewPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        syncPreviewPlaybackRate()
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
                recordBridgeSuccess()
                statusMessage = enabled ? "Launch at login enabled." : "Launch at login disabled."
                alertMessage = nil
            } catch {
                autostartEnabled = previous
                recordBridgeFailure(error, context: "set-autostart")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to update launch at login: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleBlendInterpolation(_ enabled: Bool) {
        guard !isBusy else {
            blendInterpolationEnabled = !enabled
            return
        }

        let previous = blendInterpolationEnabled
        blendInterpolationEnabled = enabled
        guard let controller else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setInterpolation(enabled) }
                apply(status: status)
                recordBridgeSuccess()
                statusMessage = enabled
                    ? "Blend interpolation enabled."
                    : "Blend interpolation disabled."
                alertMessage = nil
            } catch {
                blendInterpolationEnabled = previous
                recordBridgeFailure(error, context: "set-interpolation")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to update interpolation: \(error.localizedDescription)"
                }
            }
        }
    }

    func togglePauseOnFullscreen(_ enabled: Bool) {
        guard !isBusy else {
            pauseOnFullscreenEnabled = !enabled
            return
        }

        let previous = pauseOnFullscreenEnabled
        pauseOnFullscreenEnabled = enabled
        guard let controller else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setPauseOnFullscreen(enabled) }
                apply(status: status)
                recordBridgeSuccess()
                statusMessage = enabled
                    ? "Auto-pause on fullscreen enabled."
                    : "Auto-pause on fullscreen disabled."
                alertMessage = nil
            } catch {
                pauseOnFullscreenEnabled = previous
                recordBridgeFailure(error, context: "set-fullscreen-pause")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to update fullscreen policy: \(error.localizedDescription)"
                }
            }
        }
    }

    func setScaleMode(_ mode: WallpaperScaleMode) {
        guard !isBusy else { return }
        let previous = scaleMode
        scaleMode = mode
        guard let controller else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let status = try await runAsync { try controller.setScaleMode(mode) }
                apply(status: status)
                recordBridgeSuccess()
                statusMessage = "Scale mode: \(mode.title)."
                alertMessage = nil
            } catch {
                scaleMode = previous
                recordBridgeFailure(error, context: "set-scale")
                if bridgeFailureCount < bridgeFailureThreshold {
                    alertMessage = "Failed to update scale mode: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshMonitoring() {
        Task {
            await refreshMonitoringSnapshot(surfaceErrors: true)
        }
    }

    func openSettings() {
        closeDownloadedWallpapers()
        closeMonitoring()
        isSettingsOpen = true
    }

    func closeSettings() {
        isSettingsOpen = false
    }

    func openMonitoring() {
        closeDownloadedWallpapers()
        closeSettings()
        isMonitoringOpen = true
        monitoringErrorMessage = nil
        startMonitoringLoop()
    }

    func closeMonitoring() {
        isMonitoringOpen = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func setOptimizationEnabled(_ enabled: Bool) {
        optimizationEnabled = enabled
        persistOptimizationSettings()
    }

    func setOptimizationAllowAV1Passthrough(_ enabled: Bool) {
        optimizationAllowAV1Passthrough = enabled
        persistOptimizationSettings()
    }

    func setOptimizationTranscodeH264ToHEVC(_ enabled: Bool) {
        optimizationTranscodeH264ToHEVC = enabled
        persistOptimizationSettings()
    }

    func setOptimizationForceSoftwareAV1Encode(_ enabled: Bool) {
        if enabled && !optimizationHardwareAV1DecodeAvailable {
            optimizationForceSoftwareAV1Encode = false
            statusMessage = "AV1 force encode unavailable: no hardware AV1 decode."
            return
        }
        optimizationForceSoftwareAV1Encode = enabled
        persistOptimizationSettings()
    }

    func setOptimizationProfile(_ profile: OptimizationProfile) {
        optimizationProfile = profile
        persistOptimizationSettings()
    }

    func preview() {
        configurePreview(for: videoURL)
    }

    private func currentOptimizationSettings() -> VideoOptimizationSettings {
        VideoOptimizationSettings(
            enabled: optimizationEnabled,
            allowAV1PassthroughOnHardwareDecode: optimizationAllowAV1Passthrough,
            transcodeH264ToHEVC: optimizationTranscodeH264ToHEVC,
            forceSoftwareAV1Encode: (
                optimizationForceSoftwareAV1Encode
                && optimizationHardwareAV1DecodeAvailable
            ),
            profile: optimizationProfile
        )
    }

    private func applyOptimizationSettings(_ settings: VideoOptimizationSettings) {
        optimizationEnabled = settings.enabled
        optimizationAllowAV1Passthrough = settings.allowAV1PassthroughOnHardwareDecode
        optimizationTranscodeH264ToHEVC = settings.transcodeH264ToHEVC
        optimizationForceSoftwareAV1Encode = (
            settings.forceSoftwareAV1Encode && optimizationHardwareAV1DecodeAvailable
        )
        optimizationProfile = settings.profile
    }

    private func persistOptimizationSettings() {
        optimizationStore.save(currentOptimizationSettings())
    }

    private func prepareVideoURLForPlayback(_ sourceURL: URL) async throws -> (url: URL, summary: String?) {
        let settings = currentOptimizationSettings()
        guard settings.enabled else {
            return (sourceURL, nil)
        }

        optimizationInProgress = true
        optimizationProgress = 0
        optimizationLabel = "Preparing optimization..."
        defer {
            optimizationInProgress = false
            optimizationProgress = 0
            optimizationLabel = nil
        }

        let result = try await optimizer.optimizeIfNeeded(
            inputURL: sourceURL,
            settings: settings,
            progress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    let value = min(max(progress, 0), 1)
                    self?.optimizationProgress = value
                    let percent = Int((value * 100).rounded())
                    self?.optimizationLabel = "Optimizing video: \(percent)%"
                }
            }
        )

        switch result.decision {
        case .passthrough(let reason):
            return (result.outputURL, reason)
        case .transcode(let reason):
            let summary: String
            if result.fromCache {
                summary = "Using cached optimized video. \(reason)"
            } else {
                summary = "Video optimized for macOS playback. \(reason)"
            }
            return (result.outputURL, summary)
        }
    }

    private func apply(
        status: ControlStatus,
        refreshPreview: Bool = true,
        backgroundUpdate: Bool = false
    ) {
        isRunning = status.running
        playbackSpeed = status.config.playback_speed
        autostartEnabled = status.autostart ?? status.config.autostart ?? false
        blendInterpolationEnabled = status.config.blend_interpolation ?? false
        pauseOnFullscreenEnabled = status.config.pause_on_fullscreen ?? true
        let previousScaleMode = scaleMode
        scaleMode = WallpaperScaleMode(rawValue: status.config.scale_mode ?? "fill") ?? .fill
        if !status.config.video_path.isEmpty {
            let currentURL = URL(fileURLWithPath: status.config.video_path)
            let hasVideoChanged = videoURL?.path != currentURL.path
            videoURL = currentURL
            if refreshPreview && (hasVideoChanged || previewPlayer == nil || previousScaleMode != scaleMode) {
                configurePreview(for: currentURL)
            }
        } else {
            videoURL = nil
            previewPlayer = nil
        }
        syncPreviewPlaybackRate()
        evaluateStatusContract(status, backgroundUpdate: backgroundUpdate)
        evaluateDaemonHealth(status.health, backgroundUpdate: backgroundUpdate)
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
        guard !isShuttingDown else { return }
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
            apply(status: status, refreshPreview: false, backgroundUpdate: true)

            let healthSuspicious = status.health?.suspicious ?? false
            let shouldRecoverSuspiciousDaemon = (
                isRunning
                && status.running
                && !paused
                && hasVideo
                && healthSuspicious
                && daemonSuspiciousPolls >= daemonSuspiciousThreshold
            )

            if shouldRecover || shouldRecoverSuspiciousDaemon {
                let recoveredStatus = try await runAsync {
                    try controller.start(videoURL: nil, speed: nil)
                }
                apply(status: recoveredStatus, refreshPreview: false, backgroundUpdate: true)
                recordBridgeSuccess()
                if shouldRecoverSuspiciousDaemon {
                    statusMessage = "Daemon recovered from suspicious state."
                } else {
                    statusMessage = "Playback recovered after interruption."
                }
                alertMessage = nil
            }
        } catch {
            recordBridgeFailure(error, context: "background-health", surface: false)
        }
    }

    private func startMonitoringLoop() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshMonitoringSnapshot(surfaceErrors: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.isMonitoringOpen else { return }
                await self.refreshMonitoringSnapshot(surfaceErrors: false)
            }
        }
    }

    private func refreshMonitoringSnapshot(surfaceErrors: Bool) async {
        guard !isShuttingDown else { return }
        guard isMonitoringOpen else { return }
        guard let controller else {
            monitoringErrorMessage = "Python bridge unavailable."
            return
        }
        if isMonitoringRefreshing {
            return
        }

        isMonitoringRefreshing = true
        defer { isMonitoringRefreshing = false }

        do {
            let metrics = try await runAsync { try controller.metrics() }
            monitoringSnapshot = metrics
            monitoringErrorMessage = nil
        } catch {
            monitoringErrorMessage = error.localizedDescription
            if surfaceErrors {
                alertMessage = "Failed to refresh monitoring: \(error.localizedDescription)"
            }
        }
    }

    private func loadCatalogFromCache() async {
        if let cached = await catalogProvider.loadCachedAnimeCatalog(), !cached.isEmpty {
            catalogWallpapers = cached
        }
    }

    private func loadDownloadedCatalogWallpapers() {
        let loaded: [DownloadedCatalogWallpaper]
        do {
            let manifestURL = try downloadedCatalogManifestURL()
            guard let data = try? Data(contentsOf: manifestURL) else {
                let inferred = inferredDownloadedCatalogWallpapersFromDisk()
                downloadedCatalogWallpapers = inferred
                if !inferred.isEmpty {
                    try? persistDownloadedCatalogWallpapers(inferred)
                }
                return
            }
            loaded = try JSONDecoder().decode([DownloadedCatalogWallpaper].self, from: data)
        } catch {
            downloadedCatalogWallpapers = inferredDownloadedCatalogWallpapersFromDisk()
            return
        }

        let existing = loaded.filter { item in
            FileManager.default.fileExists(atPath: item.localURL.path)
        }
        var sorted = existing.sorted(by: { lhs, rhs in
            lhs.downloadedAt > rhs.downloadedAt
        })
        if sorted.isEmpty {
            sorted = inferredDownloadedCatalogWallpapersFromDisk()
        }
        downloadedCatalogWallpapers = sorted

        if existing.count != loaded.count {
            try? persistDownloadedCatalogWallpapers(sorted)
        }
    }

    private func refreshCatalogIfNeeded(force: Bool = false) {
        if catalogRefreshTask != nil {
            return
        }
        if !force,
           let lastCatalogRefreshAt,
           Date().timeIntervalSince(lastCatalogRefreshAt) < 60 * 60 * 6 {
            return
        }

        catalogRefreshTask = Task { [weak self] in
            guard let self else { return }
            catalogIsRefreshing = true
            defer {
                catalogIsRefreshing = false
                catalogRefreshTask = nil
            }

            do {
                let fetched = try await catalogProvider.fetchAnimeCatalog()
                guard !Task.isCancelled else { return }
                guard !fetched.isEmpty else { return }
                catalogWallpapers = fetched
                if let selectedCatalogWallpaper {
                    self.selectedCatalogWallpaper = fetched.first(where: { $0.id == selectedCatalogWallpaper.id })
                }
                lastCatalogRefreshAt = Date()
            } catch {
                if catalogWallpapers.isEmpty {
                    catalogWallpapers = CatalogWallpaper.defaultCatalog
                }
                statusMessage = "Catalog sync failed. Showing built-in list."
            }
        }
    }

    private func downloadCatalogVideo(for wallpaper: CatalogWallpaper) async throws -> URL {
        if let existing = downloadedCatalogWallpapers.first(where: { $0.wallpaperID == wallpaper.id }),
           FileManager.default.fileExists(atPath: existing.localURL.path) {
            return existing.localURL
        }

        let source = try await catalogSource(for: wallpaper)
        let widthLabel = source.width > 0 ? String(source.width) : "auto"
        let heightLabel = source.height > 0 ? String(source.height) : "auto"
        let destination = try catalogDirectoryURL().appendingPathComponent(
            "\(wallpaper.id)-\(widthLabel)x\(heightLabel).\(downloadFileExtension(for: source.url))"
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        var request = URLRequest(url: source.url)
        request.timeoutInterval = 30
        request.setValue("AuraFlow/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let sourcePageURL = wallpaper.sourcePageURL {
            request.setValue(sourcePageURL.absoluteString, forHTTPHeaderField: "Referer")
        }

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        if !isLikelyCatalogVideoResponse(response: response, sourceURL: source.url) {
            throw URLError(.cannotDecodeRawData)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func catalogSource(for wallpaper: CatalogWallpaper) async throws -> CatalogVideoSource {
        if let source = preferredSource(for: wallpaper) {
            return source
        }

        let resolvedURL = try await catalogProvider.resolveDownloadURL(for: wallpaper)
        return CatalogVideoSource(url: resolvedURL, width: 0, height: 0)
    }

    private func downloadFileExtension(for url: URL) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty {
            return "mp4"
        }
        return ext
    }

    private func isLikelyCatalogVideoResponse(response: URLResponse, sourceURL: URL) -> Bool {
        if let mime = response.mimeType?.lowercased() {
            if mime.hasPrefix("video/") || mime == "application/octet-stream" || mime == "binary/octet-stream" {
                return true
            }
            if mime.hasPrefix("text/") {
                return false
            }
        }
        let ext = sourceURL.pathExtension.lowercased()
        return ["mp4", "webm", "mov", "m4v", "gif"].contains(ext)
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

    private func downloadedCatalogManifestURL() throws -> URL {
        try catalogDirectoryURL().appendingPathComponent("downloaded-catalog.json")
    }

    private func registerDownloadedCatalogWallpaper(for wallpaper: CatalogWallpaper, localURL: URL) {
        let normalizedPath = localURL.standardizedFileURL.path
        var updated = downloadedCatalogWallpapers

        let entry = DownloadedCatalogWallpaper(
            id: wallpaper.id,
            wallpaperID: wallpaper.id,
            title: wallpaper.title,
            category: wallpaper.category,
            attribution: wallpaper.attribution,
            previewImageURL: wallpaper.previewImageURL,
            sourcePageURL: wallpaper.sourcePageURL,
            localPath: normalizedPath,
            downloadedAt: Date()
        )

        if let existingIndex = updated.firstIndex(where: { $0.id == entry.id || $0.localPath == entry.localPath }) {
            updated[existingIndex] = entry
        } else {
            updated.append(entry)
        }

        updated.sort(by: { lhs, rhs in
            lhs.downloadedAt > rhs.downloadedAt
        })
        downloadedCatalogWallpapers = updated
        try? persistDownloadedCatalogWallpapers(updated)
    }

    private func persistDownloadedCatalogWallpapers(_ wallpapers: [DownloadedCatalogWallpaper]) throws {
        let data = try JSONEncoder().encode(wallpapers)
        try data.write(to: try downloadedCatalogManifestURL(), options: .atomic)
    }

    private func syncDownloadedCatalogWallpaperAfterApply(
        wallpaperID: String,
        requestedURL: URL,
        previousVideoPath: String?
    ) {
        guard let appliedURL = videoURL?.standardizedFileURL else {
            return
        }
        let appliedPath = appliedURL.path
        if let previousVideoPath, previousVideoPath == appliedPath {
            return
        }

        var updated = downloadedCatalogWallpapers
        guard let index = updated.firstIndex(where: { $0.wallpaperID == wallpaperID }) else {
            return
        }

        let normalizedRequestedPath = requestedURL.standardizedFileURL.path
        let normalizedExistingPath = updated[index].localURL.standardizedFileURL.path
        if normalizedExistingPath == appliedPath {
            return
        }

        let normalizedPathToStore: String
        if FileManager.default.fileExists(atPath: appliedPath) {
            normalizedPathToStore = appliedPath
        } else {
            normalizedPathToStore = normalizedRequestedPath
        }

        let current = updated[index]
        updated[index] = DownloadedCatalogWallpaper(
            id: current.id,
            wallpaperID: current.wallpaperID,
            title: current.title,
            category: current.category,
            attribution: current.attribution,
            previewImageURL: current.previewImageURL,
            sourcePageURL: current.sourcePageURL,
            localPath: normalizedPathToStore,
            downloadedAt: current.downloadedAt
        )
        downloadedCatalogWallpapers = updated
        try? persistDownloadedCatalogWallpapers(updated)
    }

    private func inferredDownloadedCatalogWallpapersFromDisk() -> [DownloadedCatalogWallpaper] {
        guard let directory = try? catalogDirectoryURL() else {
            return []
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let validExtensions = Set(["mp4", "mov", "m4v", "webm", "gif"])
        let ignoredNames: Set<String> = [
            "waifu-anime-cache.json",
            "waifu-download-links.json",
            "downloaded-catalog.json",
        ]

        let mapped: [DownloadedCatalogWallpaper] = files.compactMap { fileURL in
            let name = fileURL.lastPathComponent
            guard !ignoredNames.contains(name) else { return nil }
            let ext = fileURL.pathExtension.lowercased()
            guard validExtensions.contains(ext) else { return nil }

            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let downloadedAt = values?.contentModificationDate ?? Date()
            let fileName = fileURL.deletingPathExtension().lastPathComponent

            return DownloadedCatalogWallpaper(
                id: "local-\(fileName)",
                wallpaperID: "local-\(fileName)",
                title: inferredTitleFromDownloadedFileName(fileName),
                category: "Downloaded",
                attribution: "Catalog Cache",
                previewImageURL: nil,
                sourcePageURL: nil,
                localPath: fileURL.standardizedFileURL.path,
                downloadedAt: downloadedAt
            )
        }

        return mapped.sorted(by: { lhs, rhs in
            lhs.downloadedAt > rhs.downloadedAt
        })
    }

    private func inferredTitleFromDownloadedFileName(_ fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { part in
                let word = String(part)
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
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
        player.rate = previewPlaybackRate()

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            player.seek(to: .zero)
            player.play()
            Task { @MainActor [weak self] in
                player.rate = self?.previewPlaybackRate() ?? 1.0
            }
        }

        previewPlayer = player
    }

    private func previewPlaybackRate() -> Float {
        Float(max(0.1, min(playbackSpeed, 4.0)))
    }

    private func syncPreviewPlaybackRate() {
        guard let previewPlayer else { return }
        let rate = previewPlaybackRate()
        if previewPlayer.rate == rate {
            return
        }
        previewPlayer.play()
        previewPlayer.rate = rate
    }

    private func startFromAutostartIfNeeded(using status: ControlStatus) async {
        guard !isShuttingDown else { return }
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
            recordBridgeSuccess()
            statusMessage = "Launch at login: wallpaper started."
            alertMessage = nil
        } catch {
            recordBridgeFailure(error, context: "autostart-start")
            if bridgeFailureCount < bridgeFailureThreshold {
                alertMessage = "Launch at login error: \(error.localizedDescription)"
            }
        }
    }

    private func evaluateStatusContract(
        _ status: ControlStatus,
        backgroundUpdate: Bool
    ) {
        guard let version = status.contract_version else { return }
        guard version < expectedStatusContractVersion else { return }

        daemonSuspiciousPolls = max(daemonSuspiciousPolls, daemonSuspiciousThreshold)
        let message = "Control contract mismatch (expected \(expectedStatusContractVersion), got \(version))."
        if !backgroundUpdate {
            alertMessage = message
        } else {
            statusMessage = "Daemon contract warning."
        }
    }

    private func evaluateDaemonHealth(
        _ health: DaemonHealth?,
        backgroundUpdate: Bool
    ) {
        guard let health else {
            daemonSuspiciousPolls = 0
            lowPowerAutoPauseActive = false
            fullscreenAutoPauseActive = false
            return
        }

        let autoPausedForLowPower = health.auto_paused_for_low_power ?? false
        if autoPausedForLowPower && !lowPowerAutoPauseActive {
            lowPowerAutoPauseActive = true
            statusMessage = "Low Power Mode: wallpaper paused automatically."
        } else if !autoPausedForLowPower && lowPowerAutoPauseActive {
            lowPowerAutoPauseActive = false
            statusMessage = "Low Power Mode off: wallpaper resumed."
        }

        let autoPausedForFullscreen = health.auto_paused_for_fullscreen ?? false
        if autoPausedForFullscreen && !fullscreenAutoPauseActive {
            fullscreenAutoPauseActive = true
            statusMessage = "Fullscreen app detected: wallpaper paused."
        } else if !autoPausedForFullscreen && fullscreenAutoPauseActive {
            fullscreenAutoPauseActive = false
            statusMessage = "Fullscreen app closed: wallpaper resumed."
        }

        let suspicious = health.suspicious ?? false
        if suspicious {
            daemonSuspiciousPolls += 1
            if daemonSuspiciousPolls == daemonSuspiciousThreshold {
                let reason = normalizedDaemonReason(health.reason)
                let warning = "Daemon warning: \(reason)."
                if backgroundUpdate {
                    statusMessage = warning
                } else {
                    alertMessage = warning
                }
            }
        } else {
            daemonSuspiciousPolls = 0
        }
    }

    private func normalizedDaemonReason(_ reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "unknown issue"
        }
        return trimmed.replacingOccurrences(of: ",", with: ", ")
    }

    private func configuredVideoNeedingCompatibilityNormalization(from status: ControlStatus) -> URL? {
        let path = status.config.video_path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if ["webm", "mkv"].contains(ext) {
            return url
        }
        return nil
    }

    private func beginShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        healthMonitorTask?.cancel()
        monitoringTask?.cancel()
    }

    private func recordBridgeSuccess() {
        if bridgeFailureCount >= bridgeFailureThreshold {
            statusMessage = "Python bridge recovered."
        }
        bridgeFailureCount = 0
    }

    private func recordBridgeFailure(
        _ error: Error,
        context: String,
        surface: Bool = true
    ) {
        bridgeFailureCount += 1
        let description = error.localizedDescription

        if bridgeFailureCount >= bridgeFailureThreshold {
            alertMessage = "Python bridge unstable (\(context)): \(description)"
            statusMessage = "Bridge health warning."
            return
        }

        if surface {
            alertMessage = description
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
