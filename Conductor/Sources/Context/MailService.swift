import AppKit
import Foundation

final class MailService {
    static let shared = MailService()

    private init() {}

    enum ConnectionStatus: Equatable {
        case notRunning
        case noAccess
        case connected
    }

    struct EmailSummary {
        let sender: String
        let subject: String
        let receivedDate: Date
        let isRead: Bool
        let mailbox: String
    }

    func isMailRunning() -> Bool {
        let script = """
        tell application "System Events"
            return (name of processes) contains "Mail"
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }

    func connectionStatus() -> ConnectionStatus {
        guard isMailRunning() else { return .notRunning }

        let script = """
        tell application "Mail"
            try
                return (count of accounts) > 0
            on error
                return false
            end try
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return .noAccess }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if error != nil {
            return .noAccess
        }
        return result.booleanValue ? .connected : .noAccess
    }

    @discardableResult
    func connectToMailApp() async -> ConnectionStatus {
        if !isMailRunning() {
            NSWorkspace.shared.launchApplication("Mail")
        }

        for _ in 0..<10 {
            let status = connectionStatus()
            if status != .notRunning {
                return status
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return connectionStatus()
    }

    func getRecentEmails(hoursBack: Int = 24) async -> [EmailSummary] {
        guard isMailRunning() else { return [] }

        let script = """
        tell application "Mail"
            set recentMessages to {}
            set cutoffDate to (current date) - (\(hoursBack) * hours)
            try
                set inboxMessages to messages of mailbox "INBOX" of account 1
                repeat with msg in inboxMessages
                    if date received of msg > cutoffDate then
                        set msgInfo to {sender:(sender of msg), subject:(subject of msg), dateReceived:(date received of msg), isRead:(read status of msg)}
                        set end of recentMessages to msgInfo
                    end if
                    if (count of recentMessages) > 50 then exit repeat
                end repeat
            end try
            return recentMessages
        end tell
        """

        return await executeMailQuery(script: script, mailbox: "INBOX")
    }

    func getUnreadCount() async -> Int {
        guard isMailRunning() else { return 0 }

        let script = """
        tell application "Mail"
            try
                return unread count of mailbox "INBOX" of account 1
            on error
                return 0
            end try
        end tell
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: 0)
                    return
                }
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? Int(result.int32Value) : 0)
            }
        }
    }

    private func executeMailQuery(script: String, mailbox: String) async -> [EmailSummary] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: [])
                    return
                }
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)

                if error != nil {
                    Log.mail.error("AppleScript error in mail query")
                    continuation.resume(returning: [])
                    return
                }

                var emails: [EmailSummary] = []
                let count = result.numberOfItems
                guard count > 0 else {
                    continuation.resume(returning: [])
                    return
                }

                for i in 1...count {
                    if let record = result.atIndex(i) {
                        let sender = record.atIndex(1)?.stringValue ?? ""
                        let subject = record.atIndex(2)?.stringValue ?? ""
                        let dateReceived = record.atIndex(3)?.dateValue ?? Date()
                        let isRead = record.atIndex(4)?.booleanValue ?? true

                        emails.append(EmailSummary(
                            sender: sender,
                            subject: subject,
                            receivedDate: dateReceived,
                            isRead: isRead,
                            mailbox: mailbox
                        ))
                    }
                }

                continuation.resume(returning: emails)
            }
        }
    }
}
