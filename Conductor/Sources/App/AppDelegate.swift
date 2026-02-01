import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
        ProactiveEngine.shared.stop()
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
        // Find the menubar extra window and toggle it
        for window in NSApp.windows {
            if window.className.contains("MenuBarExtra") || window.title.isEmpty {
                if window.isVisible {
                    window.orderOut(nil)
                } else {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                return
            }
        }

        // Fallback: activate the app
        NSApp.activate(ignoringOtherApps: true)
    }
}
