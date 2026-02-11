import AppKit
import SwiftUI

@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var windowDelegate: MainWindowDelegate?

    private init() {}

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    func showWindow(appState: AppState) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ConductorView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Conductor"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.setFrameAutosaveName("ConductorMainWindow")
        window.minSize = NSSize(width: 360, height: 400)

        // Center only if no saved frame
        if !window.setFrameUsingName("ConductorMainWindow") {
            window.center()
        }

        windowDelegate = MainWindowDelegate { [weak self] in
            self?.handleWindowClose()
        }
        window.delegate = windowDelegate

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func toggleWindow(appState: AppState) {
        if let window = window, window.isVisible {
            hideWindow()
        } else {
            showWindow(appState: appState)
        }
    }

    private func handleWindowClose() {
        window = nil
        windowDelegate = nil
    }
}

private class MainWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
