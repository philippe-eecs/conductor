import Foundation

/// Service for integrating with Mail.app via AppleScript
/// Queries recent emails from VIP senders and with important keywords
final class MailService {
    static let shared = MailService()

    private init() {}

    struct EmailSummary {
        let sender: String
        let subject: String
        let receivedDate: Date
        let isRead: Bool
        let mailbox: String
    }

    // Default VIP senders - users can customize via preferences
    private var vipSenders: [String] {
        if let pref = try? Database.shared.getPreference(key: "vip_email_senders"),
           !pref.isEmpty {
            return pref.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    // Important keywords to look for in subject lines
    private var importantKeywords: [String] {
        if let pref = try? Database.shared.getPreference(key: "important_email_keywords"),
           !pref.isEmpty {
            return pref.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        return ["urgent", "action required", "deadline", "asap", "important"]
    }

    /// Check if Mail.app is running
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

    /// Get recent unread emails from INBOX (last 24 hours)
    func getRecentEmails(hoursBack: Int = 24) async -> [EmailSummary] {
        guard isMailRunning() else {
            print("MailService: Mail.app is not running")
            return []
        }

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

    /// Get emails from VIP senders (last 48 hours)
    func getVIPEmails() async -> [EmailSummary] {
        guard isMailRunning(), !vipSenders.isEmpty else {
            return []
        }

        var allVIPEmails: [EmailSummary] = []

        for vipSender in vipSenders {
            let script = """
            tell application "Mail"
                set vipMessages to {}
                set cutoffDate to (current date) - (48 * hours)

                try
                    set inboxMessages to messages of mailbox "INBOX" of account 1 whose sender contains "\(vipSender)"
                    repeat with msg in inboxMessages
                        if date received of msg > cutoffDate then
                            set msgInfo to {sender:(sender of msg), subject:(subject of msg), dateReceived:(date received of msg), isRead:(read status of msg)}
                            set end of vipMessages to msgInfo
                        end if
                        if (count of vipMessages) > 10 then exit repeat
                    end repeat
                end try

                return vipMessages
            end tell
            """

            let emails = await executeMailQuery(script: script, mailbox: "INBOX")
            allVIPEmails.append(contentsOf: emails)
        }

        return allVIPEmails.sorted { $0.receivedDate > $1.receivedDate }
    }

    /// Get emails with important keywords in subject (last 24 hours)
    func getImportantEmails() async -> [EmailSummary] {
        guard isMailRunning() else {
            return []
        }

        var importantEmails: [EmailSummary] = []

        for keyword in importantKeywords {
            let script = """
            tell application "Mail"
                set importantMessages to {}
                set cutoffDate to (current date) - (24 * hours)

                try
                    set inboxMessages to messages of mailbox "INBOX" of account 1 whose subject contains "\(keyword)"
                    repeat with msg in inboxMessages
                        if date received of msg > cutoffDate then
                            set msgInfo to {sender:(sender of msg), subject:(subject of msg), dateReceived:(date received of msg), isRead:(read status of msg)}
                            set end of importantMessages to msgInfo
                        end if
                        if (count of importantMessages) > 5 then exit repeat
                    end repeat
                end try

                return importantMessages
            end tell
            """

            let emails = await executeMailQuery(script: script, mailbox: "INBOX")
            importantEmails.append(contentsOf: emails)
        }

        // Deduplicate by subject
        var seen = Set<String>()
        return importantEmails.filter { email in
            if seen.contains(email.subject) {
                return false
            }
            seen.insert(email.subject)
            return true
        }.sorted { $0.receivedDate > $1.receivedDate }
    }

    /// Get unread email count
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

                if error == nil {
                    continuation.resume(returning: Int(result.int32Value))
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    /// Build email context for morning brief
    func buildEmailContext() async -> EmailContext {
        let vipEmails = await getVIPEmails()
        let importantEmails = await getImportantEmails()
        let unreadCount = await getUnreadCount()

        // Combine and deduplicate
        var allImportant = vipEmails
        let vipSubjects = Set(vipEmails.map { $0.subject })

        for email in importantEmails {
            if !vipSubjects.contains(email.subject) {
                allImportant.append(email)
            }
        }

        return EmailContext(
            unreadCount: unreadCount,
            vipEmails: vipEmails,
            importantEmails: allImportant.sorted { $0.receivedDate > $1.receivedDate },
            hasMailAccess: isMailRunning()
        )
    }

    // MARK: - Send Email

    /// Creates an outgoing email in Mail.app with visible: true so the user can review before sending.
    func sendEmail(to: String, subject: String, body: String, cc: String? = nil) async -> Bool {
        var script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(escapeAppleScript(subject))", content:"\(escapeAppleScript(body))", visible:true}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(escapeAppleScript(to))"}
        """

        if let cc, !cc.isEmpty {
            script += """

                make new cc recipient at end of cc recipients with properties {address:"\(escapeAppleScript(cc))"}
            """
        }

        script += """

            end tell
            activate
        end tell
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: false)
                    return
                }
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error {
                    print("MailService sendEmail error: \(error)")
                    continuation.resume(returning: false)
                } else {
                    print("MailService: Email draft created for \(to)")
                    continuation.resume(returning: true)
                }
            }
        }
    }

    /// Escapes special characters for AppleScript string literals
    private func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - Private

    private func executeMailQuery(script: String, mailbox: String) async -> [EmailSummary] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: [])
                    return
                }
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)

                if let error = error {
                    print("MailService AppleScript error: \(error)")
                    continuation.resume(returning: [])
                    return
                }

                var emails: [EmailSummary] = []

                // Parse the AppleScript list result
                // Each item is a record with {sender, subject, dateReceived, isRead}
                let count = result.numberOfItems
                for i in 1...count {
                    if let record = result.atIndex(i) {
                        // AppleScript records are accessed by index (1-based)
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

// MARK: - Email Context

struct EmailContext {
    let unreadCount: Int
    let vipEmails: [MailService.EmailSummary]
    let importantEmails: [MailService.EmailSummary]
    let hasMailAccess: Bool

    var summary: String {
        guard hasMailAccess else {
            return "Email: Mail.app not running"
        }

        var parts: [String] = []

        if unreadCount > 0 {
            parts.append("\(unreadCount) unread")
        }

        if !vipEmails.isEmpty {
            parts.append("\(vipEmails.count) from VIPs")
        }

        if !importantEmails.isEmpty {
            parts.append("\(importantEmails.count) important")
        }

        return parts.isEmpty ? "No new emails" : "Email: " + parts.joined(separator: ", ")
    }
}
