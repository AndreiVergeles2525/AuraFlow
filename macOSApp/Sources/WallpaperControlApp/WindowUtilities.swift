import AppKit

let auraFlowMainWindowIdentifier = NSUserInterfaceItemIdentifier("AuraFlowMainWindow")

private final class AuraFlowMainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private let auraFlowMainWindowDelegate = AuraFlowMainWindowDelegate()

func configureWindowForClientDecorations(_ window: NSWindow) {
    window.identifier = auraFlowMainWindowIdentifier
    window.isReleasedWhenClosed = false
    window.delegate = auraFlowMainWindowDelegate
    window.tabbingMode = .disallowed
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.standardWindowButton(.closeButton)?.isHidden = false
    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
    window.standardWindowButton(.zoomButton)?.isHidden = false
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

@discardableResult
func bringMainWindowToFront() -> Bool {
    NSApp.activate(ignoringOtherApps: true)

    let targetWindow = NSApp.windows.first { $0.identifier == auraFlowMainWindowIdentifier }
    guard let window = targetWindow ?? NSApp.windows.first else {
        return false
    }

    if window.isMiniaturized {
        window.deminiaturize(nil)
    }

    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    return true
}
