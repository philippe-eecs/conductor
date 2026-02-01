import Foundation
import SwiftUI

struct Session: Identifiable {
    let id: String
    let createdAt: Date
    let lastUsed: Date
    let title: String

    var formattedLastUsed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
}

struct DailyBrief: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let briefType: BriefType
    let content: String
    let generatedAt: Date
    var readAt: Date?
    var dismissed: Bool

    enum BriefType: String, Codable {
        case morning
        case evening
        case weekly
        case monthly
    }

    init(
        id: String = UUID().uuidString,
        date: String,
        briefType: BriefType,
        content: String,
        generatedAt: Date = Date(),
        readAt: Date? = nil,
        dismissed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.briefType = briefType
        self.content = content
        self.generatedAt = generatedAt
        self.readAt = readAt
        self.dismissed = dismissed
    }
}

struct DailyGoal: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    var goalText: String
    var priority: Int
    var completedAt: Date?
    var rolledTo: String?

    var isCompleted: Bool { completedAt != nil }
    var isRolled: Bool { rolledTo != nil }

    init(
        id: String = UUID().uuidString,
        date: String,
        goalText: String,
        priority: Int = 0,
        completedAt: Date? = nil,
        rolledTo: String? = nil
    ) {
        self.id = id
        self.date = date
        self.goalText = goalText
        self.priority = priority
        self.completedAt = completedAt
        self.rolledTo = rolledTo
    }
}

struct ProductivityStats: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let goalsCompleted: Int
    let goalsTotal: Int
    let meetingsCount: Int
    let meetingsHours: Double
    let focusHours: Double
    let overdueCount: Int
    let generatedAt: Date

    var completionRate: Double {
        guard goalsTotal > 0 else { return 0 }
        return Double(goalsCompleted) / Double(goalsTotal)
    }

    init(
        id: String = UUID().uuidString,
        date: String,
        goalsCompleted: Int,
        goalsTotal: Int,
        meetingsCount: Int,
        meetingsHours: Double,
        focusHours: Double,
        overdueCount: Int,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.goalsCompleted = goalsCompleted
        self.goalsTotal = goalsTotal
        self.meetingsCount = meetingsCount
        self.meetingsHours = meetingsHours
        self.focusHours = focusHours
        self.overdueCount = overdueCount
        self.generatedAt = generatedAt
    }
}

struct TaskList: Identifiable {
    let id: String
    var name: String
    var color: String
    var icon: String
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        icon: String = "list.bullet",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var swiftUIColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        default: return .blue
        }
    }
}

struct TodoTask: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var listId: String?
    var priority: Priority
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date

    enum Priority: Int, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        var label: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        var icon: String? {
            switch self {
            case .none: return nil
            case .low: return "arrow.down"
            case .medium: return "minus"
            case .high: return "exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .none: return .secondary
            case .low: return .blue
            case .medium: return .orange
            case .high: return .red
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        listId: String? = nil,
        priority: Priority = .none,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.listId = listId
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isDueTomorrow: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }

    var isDueThisWeek: Bool {
        guard let dueDate else { return false }
        let calendar = Calendar.current
        let now = Date()
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
        return dueDate >= now && dueDate < weekEnd
    }

    var dueDateLabel: String? {
        guard let dueDate else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if isOverdue {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: dueDate, relativeTo: Date())
        } else {
            return SharedDateFormatters.shortMonthDay.string(from: dueDate)
        }
    }
}

