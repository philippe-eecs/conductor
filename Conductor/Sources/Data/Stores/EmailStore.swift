import Foundation
import SQLite

struct EmailStore: DatabaseStore {
    let database: Database

    // MARK: - Table Definition

    private static let processedEmails = Table("processed_emails")

    private static let id = Expression<String>("id")
    private static let messageId = Expression<String>("message_id")
    private static let sender = Expression<String>("sender")
    private static let subject = Expression<String>("subject")
    private static let bodyPreview = Expression<String>("body_preview")
    private static let receivedAt = Expression<Double>("received_at")
    private static let isRead = Expression<Bool>("is_read")
    private static let severity = Expression<String>("severity")
    private static let aiSummary = Expression<String?>("ai_summary")
    private static let actionItem = Expression<String?>("action_item")
    private static let processedAt = Expression<Double>("processed_at")
    private static let dismissed = Expression<Bool>("dismissed")

    // MARK: - Table Creation

    static func createTables(in db: Connection) throws {
        try db.run(processedEmails.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(messageId)
            t.column(sender)
            t.column(subject)
            t.column(bodyPreview, defaultValue: "")
            t.column(receivedAt)
            t.column(isRead, defaultValue: true)
            t.column(severity, defaultValue: "normal")
            t.column(aiSummary)
            t.column(actionItem)
            t.column(processedAt)
            t.column(dismissed, defaultValue: false)
            t.unique(messageId)
        })
    }

    // MARK: - CRUD

    func saveProcessedEmail(_ email: ProcessedEmail) throws {
        try perform { db in
            try db.run(Self.processedEmails.insert(or: .replace,
                Self.id <- email.id,
                Self.messageId <- email.messageId,
                Self.sender <- email.sender,
                Self.subject <- email.subject,
                Self.bodyPreview <- email.bodyPreview,
                Self.receivedAt <- email.receivedAt.timeIntervalSince1970,
                Self.isRead <- email.isRead,
                Self.severity <- email.severity.rawValue,
                Self.aiSummary <- email.aiSummary,
                Self.actionItem <- email.actionItem,
                Self.processedAt <- email.processedAt.timeIntervalSince1970,
                Self.dismissed <- email.dismissed
            ))
        }
    }

    func saveBatch(_ emails: [ProcessedEmail]) throws {
        for email in emails {
            try saveProcessedEmail(email)
        }
    }

    func getProcessedEmails(filter: EmailFilter = .all, limit: Int = 50) throws -> [ProcessedEmail] {
        try perform { db in
            var query = Self.processedEmails.order(Self.receivedAt.desc).limit(limit)

            switch filter {
            case .all:
                query = query.filter(Self.dismissed == false)
            case .actionNeeded:
                query = query.filter(Self.actionItem != nil && Self.dismissed == false)
            case .important:
                query = query.filter(
                    (Self.severity == EmailSeverity.critical.rawValue || Self.severity == EmailSeverity.important.rawValue)
                    && Self.dismissed == false
                )
            case .dismissed:
                query = query.filter(Self.dismissed == true)
            }

            return try db.prepare(query).map(parseProcessedEmail)
        }
    }

    func getUnprocessedCount() throws -> Int {
        try perform { db in
            try db.scalar(
                Self.processedEmails
                    .filter(Self.dismissed == false)
                    .filter(Self.severity == EmailSeverity.critical.rawValue || Self.severity == EmailSeverity.important.rawValue)
                    .count
            )
        }
    }

    func getActionNeededCount() throws -> Int {
        try perform { db in
            try db.scalar(
                Self.processedEmails
                    .filter(Self.actionItem != nil && Self.dismissed == false)
                    .count
            )
        }
    }

    func dismissEmail(id emailId: String) throws {
        try perform { db in
            try db.run(Self.processedEmails.filter(Self.id == emailId).update(Self.dismissed <- true))
        }
    }

    func getEmail(id emailId: String) throws -> ProcessedEmail? {
        try perform { db in
            guard let row = try db.pluck(Self.processedEmails.filter(Self.id == emailId)) else {
                return nil
            }
            return parseProcessedEmail(from: row)
        }
    }

    // MARK: - Parsing

    private func parseProcessedEmail(from row: Row) -> ProcessedEmail {
        ProcessedEmail(
            id: row[Self.id],
            messageId: row[Self.messageId],
            sender: row[Self.sender],
            subject: row[Self.subject],
            bodyPreview: row[Self.bodyPreview],
            receivedAt: Date(timeIntervalSince1970: row[Self.receivedAt]),
            isRead: row[Self.isRead],
            severity: EmailSeverity(rawValue: row[Self.severity]) ?? .normal,
            aiSummary: row[Self.aiSummary],
            actionItem: row[Self.actionItem],
            processedAt: Date(timeIntervalSince1970: row[Self.processedAt]),
            dismissed: row[Self.dismissed]
        )
    }
}

// MARK: - Models

struct ProcessedEmail: Identifiable {
    let id: String
    let messageId: String
    let sender: String
    let subject: String
    let bodyPreview: String
    let receivedAt: Date
    let isRead: Bool
    let severity: EmailSeverity
    let aiSummary: String?
    let actionItem: String?
    let processedAt: Date
    var dismissed: Bool

    init(
        id: String = UUID().uuidString,
        messageId: String,
        sender: String,
        subject: String,
        bodyPreview: String = "",
        receivedAt: Date = Date(),
        isRead: Bool = true,
        severity: EmailSeverity = .normal,
        aiSummary: String? = nil,
        actionItem: String? = nil,
        processedAt: Date = Date(),
        dismissed: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.sender = sender
        self.subject = subject
        self.bodyPreview = bodyPreview
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.severity = severity
        self.aiSummary = aiSummary
        self.actionItem = actionItem
        self.processedAt = processedAt
        self.dismissed = dismissed
    }

    var formattedReceivedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: receivedAt, relativeTo: Date())
    }
}

enum EmailSeverity: String, Codable, CaseIterable {
    case critical
    case important
    case normal
    case low
}

enum EmailFilter: String, CaseIterable {
    case all = "All"
    case actionNeeded = "Action Needed"
    case important = "Important"
    case dismissed = "Dismissed"
}
