import Cocoa
import Carbon
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?
    private var badgeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep running in background without dock icon
        NSApp.setActivationPolicy(.accessory)

        // Register global hotkey (Cmd+Shift+C)
        registerGlobalHotkey()

        // Initialize database
        _ = Database.shared

        // Initialize notification manager (sets up actionable notification categories)
        _ = NotificationManager.shared

        // Start proactive engine (event-driven scheduling)
        ProactiveEngine.shared.start()

        // Set up menu bar status item
        setupStatusItem()

        // Show window on launch
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
        ProactiveEngine.shared.stop()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusItemIcon(hasBadge: AppState.shared.showPlanningNotificationBadge)

            // Left-click toggles window
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Observe badge changes
        badgeCancellable = AppState.shared.$showPlanningNotificationBadge
            .receive(on: RunLoop.main)
            .sink { [weak self] hasBadge in
                self?.updateStatusItemIcon(hasBadge: hasBadge)
            }
    }

    private func updateStatusItemIcon(hasBadge: Bool) {
        guard let button = statusItem?.button else { return }
        if hasBadge {
            // Use a composed image with badge
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let brainImage = NSImage(systemSymbolName: "brain", accessibilityDescription: "Conductor")?.withSymbolConfiguration(config) {
                let badgedImage = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
                    brainImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                    // Draw red dot badge
                    NSColor.red.setFill()
                    let badgeRect = NSRect(x: 15, y: 12, width: 6, height: 6)
                    NSBezierPath(ovalIn: badgeRect).fill()
                    return true
                }
                badgedImage.isTemplate = false
                button.image = badgedImage
            }
        } else {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Conductor")
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

        let planningItem = NSMenuItem(title: "Daily Planning...", action: #selector(showPlanning), keyEquivalent: "p")
        planningItem.target = self
        menu.addItem(planningItem)

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
        // Remove menu after showing so left-click works again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func openConductor() {
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    @objc private func showPlanning() {
        MainWindowController.shared.showWindow(appState: AppState.shared)
        NotificationCenter.default.post(name: .showPlanningView, object: nil)
    }

    @objc private func newConversation() {
        AppState.shared.startNewConversation()
        MainWindowController.shared.showWindow(appState: AppState.shared)
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Global Hotkey

    private func registerGlobalHotkey() {
        // Cmd+Shift+C hotkey
        // Key code for 'C' is 8
        let hotKeyID = EventHotKeyID(signature: OSType(0x434F4E44), id: 1) // 'COND'

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
            print("Global hotkey registered: Cmd+Shift+C")
        } else {
            print("Failed to register global hotkey: \(status)")
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
