import Foundation

enum RuntimeEnvironment {
    static var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// True when the current process can safely show macOS privacy (TCC) permission prompts.
    static var supportsTCCPrompts: Bool { isRunningInAppBundle }

    /// True when `UNUserNotificationCenter.current()` is safe to call.
    static var supportsUserNotifications: Bool { isRunningInAppBundle }
}

