import Testing
import AVFoundation
@testable import WallpaperControlApp

@MainActor
@Test func previewSetsPlayerWhenVideoSelected() throws {
    let controller = MockPythonController()
    let viewModel = AppViewModel(controller: controller)

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preview-test.mp4")
    FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
    defer {
        try? FileManager.default.removeItem(at: tempURL)
    }

    viewModel.videoURL = tempURL
    viewModel.preview()

    #expect(viewModel.previewPlayer != nil)
    #expect(viewModel.previewPlayer?.currentItem != nil)
}

@MainActor
@Test func catalogBackNavigatesDetailThenExitsCatalog() throws {
    let controller = MockPythonController()
    let viewModel = AppViewModel(controller: controller)

    viewModel.openCatalog()
    #expect(viewModel.isCatalogOpen)

    let wallpaper = try #require(viewModel.catalogWallpapers.first)
    viewModel.openCatalogWallpaper(wallpaper)
    #expect(viewModel.selectedCatalogWallpaper == wallpaper)

    viewModel.navigateBackFromCatalog()
    #expect(viewModel.selectedCatalogWallpaper == nil)
    #expect(viewModel.isCatalogOpen)

    viewModel.navigateBackFromCatalog()
    #expect(viewModel.isCatalogOpen == false)
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

    func start(videoURL: URL?, speed: Double?) throws -> ControlStatus {
        try status()
    }

    func stop() throws -> ControlStatus {
        try status()
    }

    func clearWallpaper() throws -> ControlStatus {
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
