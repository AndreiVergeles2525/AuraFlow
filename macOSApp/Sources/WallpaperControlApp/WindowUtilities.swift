import AppKit

func configureWindowForClientDecorations(_ window: NSWindow) {
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
}

func mainScreenAspectRatio() -> CGFloat {
    let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    guard frame.height != 0 else { return 16.0 / 9.0 }
    return frame.width / frame.height
}

func preferredWindowSize() -> CGSize {
    let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let aspect = mainScreenAspectRatio()
    let width = max(frame.width * 0.5, 960)
    let height = width / aspect
    return CGSize(width: width, height: height)
}
