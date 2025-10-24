#if canImport(XCTest)
import XCTest
import AVFoundation
@testable import WallpaperControlApp

@MainActor
final class AppViewModelTests: XCTestCase {
    func testPreviewSetsPlayerWhenVideoSelected() throws {
        let controller = MockPythonController()
        let viewModel = AppViewModel(controller: controller)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preview-test.mp4")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        viewModel.videoURL = tempURL
        viewModel.preview()

        XCTAssertNotNil(viewModel.previewPlayer)
        XCTAssertNotNil(viewModel.previewPlayer?.currentItem)
    }
}

final class MockPythonController: PythonControlling {
    func status() throws -> ControlStatus {
        ControlStatus(
            running: false,
            config: ControlConfig(video_path: "", playback_speed: 1.0, volume: 0.0, autostart: false),
            pid: nil,
            autostart: false
        )
    }

    func start(videoURL: URL?, speed: Double) throws -> ControlStatus {
        try status()
    }

    func stop() throws -> ControlStatus {
        try status()
    }

    func setVideo(_ url: URL) throws -> ControlStatus {
        try status()
    }

    func setSpeed(_ speed: Double) throws -> ControlStatus {
        try status()
    }

    func setAutostart(_ enabled: Bool) throws -> ControlStatus {
        try status()
    }
}
#endif
