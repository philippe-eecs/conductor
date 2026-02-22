import AppKit
import SwiftUI

@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var windowDelegate: MainWindowDelegate?
    private var detachedWindows: [WorkspaceSurface: NSWindow] = [:]
    private var detachedDelegates: [WorkspaceSurface: DetachedSurfaceWindowDelegate] = [:]

    private init() {}

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    func showWindow(appState: AppState) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.promptForPermissionsIfNeeded()
            return
        }

        let contentView = ConductorView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Conductor"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.setFrameAutosaveName("ConductorMainWindow")
        window.minSize = NSSize(width: 980, height: 660)

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
        appState.promptForPermissionsIfNeeded()
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

    func showDetachedSurfaceWindow(for surface: WorkspaceSurface, appState: AppState) {
        if let window = detachedWindows[surface] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DetachedSurfaceWindowView(surface: surface)
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Conductor - \(surface.title)"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.setFrameAutosaveName("ConductorSurfaceWindow-\(surface.rawValue)")
        window.minSize = NSSize(width: 680, height: 460)
        if !window.setFrameUsingName("ConductorSurfaceWindow-\(surface.rawValue)") {
            window.center()
        }

        let delegate = DetachedSurfaceWindowDelegate { [weak self] in
            self?.handleDetachedWindowClose(surface)
        }
        window.delegate = delegate

        detachedWindows[surface] = window
        detachedDelegates[surface] = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeDetachedSurfaceWindow(for surface: WorkspaceSurface) {
        guard let window = detachedWindows[surface] else { return }
        window.close()
    }

    func restoreDetachedWindows(appState: AppState) {
        for surface in appState.detachedSurfaces {
            showDetachedSurfaceWindow(for: surface, appState: appState)
        }
    }

    private func handleWindowClose() {
        window = nil
        windowDelegate = nil
    }

    private func handleDetachedWindowClose(_ surface: WorkspaceSurface) {
        detachedWindows[surface] = nil
        detachedDelegates[surface] = nil
        AppState.shared.handleDetachedWindowClosed(surface)
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

private class DetachedSurfaceWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
