import Foundation
import GRDB

struct ContentRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Notes

    func saveNote(title: String, content: String) throws -> String {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO notes (id, title, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [id, title, content, now, now]
            )
        }
        return id
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        try db.write { db in
            var sets: [String] = ["updated_at = ?"]
            var args: [DatabaseValueConvertible?] = [Date().timeIntervalSince1970]
            if let title { sets.append("title = ?"); args.append(title) }
            if let content { sets.append("content = ?"); args.append(content) }
            args.append(id)
            try db.execute(
                sql: "UPDATE notes SET \(sets.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(args)!
            )
        }
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, title, content FROM notes ORDER BY updated_at DESC LIMIT ?",
                arguments: [limit]
            ).map { row in
                (id: row["id"] as String, title: row["title"] as String, content: row["content"] as String)
            }
        }
    }

    func deleteNote(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Daily Briefs

    func saveDailyBrief(_ brief: DailyBrief) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO daily_briefs
                    (id, date, brief_type, content, generated_at, read_at, dismissed)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    brief.id, brief.date, brief.briefType.rawValue, brief.content,
                    brief.generatedAt.timeIntervalSince1970,
                    brief.readAt?.timeIntervalSince1970,
                    brief.dismissed ? 1 : 0,
                ]
            )
        }
    }

    func getDailyBrief(for date: String, type: DailyBrief.BriefType) throws -> DailyBrief? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM daily_briefs WHERE date = ? AND brief_type = ? LIMIT 1",
                arguments: [date, type.rawValue]
            ) else { return nil }
            return Self.parseBrief(from: row)
        }
    }

    func markBriefAsRead(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_briefs SET read_at = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, id]
            )
        }
    }

    func markBriefAsDismissed(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_briefs SET dismissed = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func getRecentBriefs(limit: Int = 7) throws -> [DailyBrief] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM daily_briefs ORDER BY generated_at DESC LIMIT ?",
                arguments: [limit]
            ).map { Self.parseBrief(from: $0) }
        }
    }

    // MARK: - Daily Goals

    func saveDailyGoal(_ goal: DailyGoal) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO daily_goals
                    (id, date, goal_text, priority, completed_at, rolled_to)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    goal.id, goal.date, goal.goalText, goal.priority,
                    goal.completedAt?.timeIntervalSince1970,
                    goal.rolledTo,
                ]
            )
        }
    }

    func getGoalsForDate(_ date: String) throws -> [DailyGoal] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM daily_goals WHERE date = ? ORDER BY priority DESC",
                arguments: [date]
            ).map { Self.parseGoal(from: $0) }
        }
    }

    func markGoalCompleted(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_goals SET completed_at = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, id]
            )
        }
    }

    func markGoalIncomplete(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_goals SET completed_at = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func rollGoalToDate(id: String, newDate: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_goals SET rolled_to = ? WHERE id = ?",
                arguments: [newDate, id]
            )
        }
    }

    func deleteGoal(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM daily_goals WHERE id = ?", arguments: [id])
        }
    }

    func updateGoalText(id: String, text: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_goals SET goal_text = ? WHERE id = ?",
                arguments: [text, id]
            )
        }
    }

    func updateGoalPriority(id: String, priority: Int) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE daily_goals SET priority = ? WHERE id = ?",
                arguments: [priority, id]
            )
        }
    }

    func getIncompleteGoals(before date: String) throws -> [DailyGoal] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM daily_goals
                    WHERE date < ? AND completed_at IS NULL AND rolled_to IS NULL
                    ORDER BY date DESC, priority DESC
                    """,
                arguments: [date]
            ).map { Self.parseGoal(from: $0) }
        }
    }

    func getGoalCompletionRate(forDays days: Int = 7) throws -> Double {
        try db.read { db in
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let dateStr = SharedDateFormatters.databaseDate.string(from: startDate)

            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM daily_goals WHERE date >= ?",
                arguments: [dateStr]
            ) ?? 0

            guard total > 0 else { return 0 }

            let completed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM daily_goals WHERE date >= ? AND completed_at IS NOT NULL",
                arguments: [dateStr]
            ) ?? 0

            return Double(completed) / Double(total)
        }
    }

    // MARK: - Productivity Stats

    func saveProductivityStats(_ stats: ProductivityStats) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO productivity_stats
                    (id, date, goals_completed, goals_total, meetings_count,
                     meetings_hours, focus_hours, overdue_count, generated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    stats.id, stats.date, stats.goalsCompleted, stats.goalsTotal,
                    stats.meetingsCount, stats.meetingsHours, stats.focusHours,
                    stats.overdueCount, stats.generatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func getProductivityStats(for date: String) throws -> ProductivityStats? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM productivity_stats WHERE date = ?",
                arguments: [date]
            ) else { return nil }
            return Self.parseStats(from: row)
        }
    }

    func getProductivityStatsRange(from startDate: String, to endDate: String) throws -> [ProductivityStats] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM productivity_stats WHERE date >= ? AND date <= ? ORDER BY date ASC",
                arguments: [startDate, endDate]
            ).map { Self.parseStats(from: $0) }
        }
    }

    func getRecentProductivityStats(days: Int = 30) throws -> [ProductivityStats] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
        return try getProductivityStatsRange(
            from: SharedDateFormatters.databaseDate.string(from: startDate),
            to: SharedDateFormatters.databaseDate.string(from: endDate)
        )
    }

    // MARK: - Context Library

    func saveContextLibraryItem(_ item: ContextLibraryItem) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO context_library (id, title, content, type, created_at, auto_include)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    item.id, item.title, item.content, item.type.rawValue,
                    item.createdAt.timeIntervalSince1970, item.autoInclude,
                ]
            )
        }
    }

    func updateContextLibraryItem(id: String, title: String? = nil, content: String? = nil, autoInclude: Bool? = nil) throws {
        try db.write { db in
            var sets: [String] = []
            var args: [DatabaseValueConvertible?] = []
            if let title { sets.append("title = ?"); args.append(title) }
            if let content { sets.append("content = ?"); args.append(content) }
            if let autoInclude { sets.append("auto_include = ?"); args.append(autoInclude) }
            guard !sets.isEmpty else { return }
            args.append(id)
            try db.execute(
                sql: "UPDATE context_library SET \(sets.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(args)!
            )
        }
    }

    func getAllContextLibraryItems() throws -> [ContextLibraryItem] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM context_library ORDER BY created_at DESC"
            ).map { Self.parseContextItem(from: $0) }
        }
    }

    func getAutoIncludeContextLibraryItems() throws -> [ContextLibraryItem] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM context_library WHERE auto_include = 1 ORDER BY created_at DESC"
            ).map { Self.parseContextItem(from: $0) }
        }
    }

    func getContextLibraryItem(id: String) throws -> ContextLibraryItem? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM context_library WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            return Self.parseContextItem(from: row)
        }
    }

    func deleteContextLibraryItem(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM context_library WHERE id = ?", arguments: [id])
        }
    }

    func getContextLibraryItemCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM context_library") ?? 0
        }
    }

    // MARK: - Processed Emails

    func saveProcessedEmail(_ email: ProcessedEmail) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO processed_emails
                    (id, message_id, sender, subject, body_preview, received_at,
                     is_read, severity, ai_summary, action_item, processed_at, dismissed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    email.id, email.messageId, email.sender, email.subject,
                    email.bodyPreview, email.receivedAt.timeIntervalSince1970,
                    email.isRead, email.severity.rawValue,
                    email.aiSummary, email.actionItem,
                    email.processedAt.timeIntervalSince1970, email.dismissed,
                ]
            )
        }
    }

    func saveProcessedEmails(_ emails: [ProcessedEmail]) throws {
        try db.write { db in
            for email in emails {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO processed_emails
                        (id, message_id, sender, subject, body_preview, received_at,
                         is_read, severity, ai_summary, action_item, processed_at, dismissed)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        email.id, email.messageId, email.sender, email.subject,
                        email.bodyPreview, email.receivedAt.timeIntervalSince1970,
                        email.isRead, email.severity.rawValue,
                        email.aiSummary, email.actionItem,
                        email.processedAt.timeIntervalSince1970, email.dismissed,
                    ]
                )
            }
        }
    }

    func getProcessedEmails(filter: EmailFilter = .all, limit: Int = 50) throws -> [ProcessedEmail] {
        try db.read { db in
            let whereClause: String
            switch filter {
            case .all:
                whereClause = "WHERE dismissed = 0"
            case .actionNeeded:
                whereClause = "WHERE action_item IS NOT NULL AND dismissed = 0"
            case .important:
                whereClause = "WHERE severity IN ('critical', 'important') AND dismissed = 0"
            case .dismissed:
                whereClause = "WHERE dismissed = 1"
            }
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM processed_emails \(whereClause) ORDER BY received_at DESC LIMIT ?",
                arguments: [limit]
            ).map { Self.parseEmail(from: $0) }
        }
    }

    func getEmailActionNeededCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM processed_emails WHERE action_item IS NOT NULL AND dismissed = 0"
            ) ?? 0
        }
    }

    func dismissProcessedEmail(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE processed_emails SET dismissed = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Parsing

    private static func parseBrief(from row: Row) -> DailyBrief {
        let readAtVal: Double? = row["read_at"]
        return DailyBrief(
            id: row["id"],
            date: row["date"],
            briefType: DailyBrief.BriefType(rawValue: row["brief_type"]) ?? .morning,
            content: row["content"],
            generatedAt: Date(timeIntervalSince1970: row["generated_at"]),
            readAt: readAtVal.map { Date(timeIntervalSince1970: $0) },
            dismissed: (row["dismissed"] as Int) != 0
        )
    }

    private static func parseGoal(from row: Row) -> DailyGoal {
        let completedAtVal: Double? = row["completed_at"]
        return DailyGoal(
            id: row["id"],
            date: row["date"],
            goalText: row["goal_text"],
            priority: row["priority"],
            completedAt: completedAtVal.map { Date(timeIntervalSince1970: $0) },
            rolledTo: row["rolled_to"]
        )
    }

    private static func parseStats(from row: Row) -> ProductivityStats {
        ProductivityStats(
            id: row["id"],
            date: row["date"],
            goalsCompleted: row["goals_completed"],
            goalsTotal: row["goals_total"],
            meetingsCount: row["meetings_count"],
            meetingsHours: row["meetings_hours"],
            focusHours: row["focus_hours"],
            overdueCount: row["overdue_count"],
            generatedAt: Date(timeIntervalSince1970: row["generated_at"])
        )
    }

    private static func parseContextItem(from row: Row) -> ContextLibraryItem {
        ContextLibraryItem(
            id: row["id"],
            title: row["title"],
            content: row["content"],
            type: ContextLibraryItem.ItemType(rawValue: row["type"]) ?? .note,
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            autoInclude: row["auto_include"]
        )
    }

    private static func parseEmail(from row: Row) -> ProcessedEmail {
        ProcessedEmail(
            id: row["id"],
            messageId: row["message_id"],
            sender: row["sender"],
            subject: row["subject"],
            bodyPreview: row["body_preview"],
            receivedAt: Date(timeIntervalSince1970: row["received_at"]),
            isRead: row["is_read"],
            severity: EmailSeverity(rawValue: row["severity"]) ?? .normal,
            aiSummary: row["ai_summary"],
            actionItem: row["action_item"],
            processedAt: Date(timeIntervalSince1970: row["processed_at"]),
            dismissed: row["dismissed"]
        )
    }
}
