#if canImport(XCTest)
import XCTest
import AppKit
@testable import WallpaperControlApp

final class WindowUtilitiesTests: XCTestCase {
    func testConfigureWindowForClientSideDecoration() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        configureWindowForClientDecorations(window)

        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden ?? false)
    }
}
#endif
