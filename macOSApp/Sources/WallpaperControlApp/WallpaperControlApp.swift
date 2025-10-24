import AppKit
import SwiftUI
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setenv("PYTHON_EXECUTABLE", "/usr/bin/python3", 1)
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct WallpaperControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: preferredWindowSize().width, height: preferredWindowSize().height)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
