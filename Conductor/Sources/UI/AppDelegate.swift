import Cocoa
import Carbon
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        registerGlobalHotkey()

        // Initialize database
        _ = AppDatabase.shared

        // Initialize notification manager
        _ = NotificationManager.shared

        // Start MCP server
        MCPServer.shared.startWithRetry()

        // Start Blink Engine
        Task { await BlinkEngine.shared.start() }

        // Set up menu bar
        setupStatusItem()

        // Load initial data and show window
        AppState.shared.loadInitialData()
        let autoOpenMail = ((try? AppState.shared.prefRepo.getInt("mail_auto_open_on_launch", default: 0)) ?? 0) == 1
        if autoOpenMail {
            Task {
                _ = await MailService.shared.connectToMailApp()
                await AppState.shared.refreshMailStatus()
            }
        }
        MainWindowController.shared.showWindow(appState: AppState.shared)
        MainWindowController.shared.restoreDetachedWindows(appState: AppState.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
        Task { await BlinkEngine.shared.stop() }
        MCPServer.shared.stop()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Conductor")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            MainWindowController.shared.toggleWindow(appState: AppState.shared)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Conductor", action: #selector(openConductor), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let newConvoItem = NSMenuItem(title: "New Conversation", action: #selector(newConversation), keyEquivalent: "n")
        newConvoItem.target = self
        menu.addItem(newConvoItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Conductor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func openConductor() {
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    @objc private func newConversation() {
        AppState.shared.startNewConversation()
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    @objc private func openSettings() {
        AppState.shared.showSettings = true
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Global Hotkey

    private func registerGlobalHotkey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434F4E44), id: 1)

        var gMyHotKeyRef: EventHotKeyRef?
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 8 // 'C' key

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &gMyHotKeyRef
        )

        if status == noErr {
            hotKeyRef = gMyHotKeyRef
            installHotKeyHandler()
            Log.app.info("Global hotkey registered: Cmd+Shift+C")
        } else {
            Log.app.error("Failed to register global hotkey: \(status)")
        }
    }

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerBlock: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, event, _ in
            guard let event = event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    AppDelegate.toggleConductorWindow()
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    private func unregisterGlobalHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    static func toggleConductorWindow() {
        MainWindowController.shared.toggleWindow(appState: AppState.shared)
    }
}
