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
}

protocol PythonControlling {
    func status() throws -> ControlStatus
    func start(videoURL: URL?, speed: Double) throws -> ControlStatus
    func stop() throws -> ControlStatus
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

    func start(videoURL: URL?, speed: Double) throws -> ControlStatus {
        var args: [String] = []
        if let videoURL {
            args.append(contentsOf: ["--video", videoURL.path])
        }
        args.append(contentsOf: ["--speed", String(speed)])
        return try run(command: "start", arguments: args)
    }

    func stop() throws -> ControlStatus {
        try run(command: "stop")
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
    @Published var statusMessage: String?
    @Published var alertMessage: String?
    @Published var previewPlayer: AVPlayer?

    private let controller: PythonControlling?

    var isControllerAvailable: Bool {
        controller != nil
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
        Task {
            await loadStatus()
        }
    }

    func loadStatus() async {
        guard let controller else {
            alertMessage = "Python bridge unavailable."
            return
        }
        do {
            let status = try await runAsync { try controller.status() }
            apply(status: status)
            alertMessage = nil
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            videoURL = url
            Task {
                await applyVideoSelection(url)
            }
        }
    }

    func applyVideoSelection(_ url: URL) async {
        guard let controller else { return }
        do {
            let status = try await runAsync { try controller.setVideo(url) }
            apply(status: status)
            statusMessage = "Видео обновлено."
            alertMessage = nil
        } catch {
            alertMessage = "Не удалось установить видео: \(error.localizedDescription)"
        }
    }

    func start() {
        guard let controller else { return }
        guard videoURL != nil else {
            alertMessage = "Выберите видео перед запуском."
            return
        }

        let selectedURL = videoURL
        let currentSpeed = playbackSpeed

        Task { [controller] in
            do {
                let status = try await runAsync {
                    try controller.start(videoURL: selectedURL, speed: currentSpeed)
                }
                apply(status: status)
                statusMessage = "Обои запущены."
                alertMessage = nil
            } catch {
                alertMessage = "Ошибка запуска: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard let controller else { return }
        Task {
            do {
                let status = try await runAsync { try controller.stop() }
                apply(status: status)
                statusMessage = "Обои остановлены."
                alertMessage = nil
            } catch {
                alertMessage = "Ошибка остановки: \(error.localizedDescription)"
            }
        }
    }

    func updateSpeed(_ speed: Double) {
        playbackSpeed = speed
        guard let controller else { return }
        Task {
            do {
                let status = try await runAsync { try controller.setSpeed(speed) }
                apply(status: status)
                statusMessage = "Скорость обновлена."
                alertMessage = nil
            } catch {
                alertMessage = "Ошибка изменения скорости: \(error.localizedDescription)"
            }
        }
    }

    func toggleAutostart(_ enabled: Bool) {
        let previous = autostartEnabled
        autostartEnabled = enabled
        guard let controller else { return }
        Task {
            do {
                let status = try await runAsync { try controller.setAutostart(enabled) }
                apply(status: status)
                statusMessage = enabled ? "Автозапуск включен." : "Автозапуск отключен."
                alertMessage = nil
            } catch {
                autostartEnabled = previous
                alertMessage = "Ошибка автозапуска: \(error.localizedDescription)"
            }
        }
    }

    func preview() {
        guard let url = videoURL else { return }
        previewPlayer = AVPlayer(url: url)
        previewPlayer?.play()
    }

    private func apply(status: ControlStatus) {
        isRunning = status.running
        playbackSpeed = status.config.playback_speed
        autostartEnabled = status.autostart ?? status.config.autostart ?? false
        if !status.config.video_path.isEmpty {
            videoURL = URL(fileURLWithPath: status.config.video_path)
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
