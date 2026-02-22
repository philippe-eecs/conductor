import Foundation

enum WorkspaceSurface: String, CaseIterable, Codable, Identifiable {
    case dashboard
    case calendar
    case tasks
    case chat
    case projects
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .chat: return "Chat"
        case .projects: return "Projects"
        case .email: return "Email"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        case .chat: return "bubble.left.and.bubble.right"
        case .projects: return "folder"
        case .email: return "envelope"
        }
    }

    static var navigationOrder: [WorkspaceSurface] {
        [.dashboard, .calendar, .tasks, .chat, .projects, .email]
    }
}

enum WorkspaceDockTarget {
    case primary
    case secondary
}
