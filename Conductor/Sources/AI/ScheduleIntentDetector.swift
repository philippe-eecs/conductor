import Foundation

/// Detects user intent to see schedule/day overview
struct ScheduleIntentDetector {
    enum Intent {
        case dayOverview
        case weekOverview
    }

    /// Detect if the user is asking about their schedule
    static func detect(_ input: String) -> Intent? {
        let q = input.lowercased()

        // Day overview patterns
        let dayPatterns = [
            "what's my day",
            "what is my day",
            "whats my day",
            "my day look",
            "today look",
            "my schedule today",
            "today's schedule",
            "todays schedule",
            "what do i have today",
            "what's on today",
            "what is on today",
            "whats on today",
            "what's today",
            "show me today",
            "my agenda",
            "today's agenda",
            "todays agenda"
        ]

        for pattern in dayPatterns {
            if q.contains(pattern) {
                return .dayOverview
            }
        }

        // Check for "today" with schedule-related words
        if q.contains("today") && (q.contains("schedule") || q.contains("plan") || q.contains("agenda") || q.contains("calendar")) {
            return .dayOverview
        }

        // Week overview patterns
        let weekPatterns = [
            "what's my week",
            "what is my week",
            "whats my week",
            "my week look",
            "this week look",
            "my schedule this week",
            "this week's schedule",
            "this weeks schedule",
            "what do i have this week",
            "week ahead",
            "weekly schedule",
            "show me this week"
        ]

        for pattern in weekPatterns {
            if q.contains(pattern) {
                return .weekOverview
            }
        }

        // Check for "week" with schedule-related words
        if q.contains("week") && (q.contains("schedule") || q.contains("plan") || q.contains("agenda") || q.contains("calendar")) {
            return .weekOverview
        }

        return nil
    }
}
