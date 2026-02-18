import Foundation

struct ChatIntentRouter {
    enum Intent {
        case dayReview
        case scheduleExactTime
        case organizeToday
        case planDay
        case themeAssignment
        case general
    }

    static func detect(_ input: String) -> Intent {
        let q = input.lowercased()

        if q.contains("day review") || q.contains("what's on my day") || q.contains("today overview") || q.contains("today agenda") {
            return .dayReview
        }

        if q.contains("plan my day") || q.contains("plan today") || q.contains("block schedule") || q.contains("organize my day") || q.contains("day plan") {
            return .planDay
        }

        if q.contains("between") || q.contains("at ") || q.contains("block") || q.contains("schedule") || q.contains("6:") || q.contains("pm") {
            return .scheduleExactTime
        }

        if q.contains("time block") || q.contains("auto organize") {
            return .organizeToday
        }

        if q.contains("theme") || q.contains("group") || q.contains("assign") {
            return .themeAssignment
        }

        return .general
    }
}
