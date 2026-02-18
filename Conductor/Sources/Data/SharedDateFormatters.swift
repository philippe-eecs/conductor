import Foundation

enum SharedDateFormatters {
    private static let dateFormatterPrefix = "com.conductor.dateformatter."
    private static let isoFormatterPrefix = "com.conductor.iso8601formatter."

    private static func cachedDateFormatter(
        key: String,
        configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let dictKey = dateFormatterPrefix + key

        if let existing = Thread.current.threadDictionary[dictKey] as? DateFormatter {
            return existing
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        configure(formatter)
        Thread.current.threadDictionary[dictKey] = formatter
        return formatter
    }

    private static func cachedISO8601Formatter(
        key: String,
        configure: (ISO8601DateFormatter) -> Void
    ) -> ISO8601DateFormatter {
        let dictKey = isoFormatterPrefix + key

        if let existing = Thread.current.threadDictionary[dictKey] as? ISO8601DateFormatter {
            return existing
        }

        let formatter = ISO8601DateFormatter()
        configure(formatter)
        Thread.current.threadDictionary[dictKey] = formatter
        return formatter
    }

    static var databaseDate: DateFormatter {
        cachedDateFormatter(key: "databaseDate") {
            $0.calendar = Calendar(identifier: .gregorian)
            $0.dateFormat = "yyyy-MM-dd"
        }
    }

    static var time12Hour: DateFormatter {
        cachedDateFormatter(key: "time12Hour") { $0.dateFormat = "h:mm a" }
    }

    static var fullDate: DateFormatter {
        cachedDateFormatter(key: "fullDate") { $0.dateFormat = "EEEE, MMMM d, yyyy" }
    }

    static var fullDateNoYear: DateFormatter {
        cachedDateFormatter(key: "fullDateNoYear") { $0.dateFormat = "EEEE, MMMM d" }
    }

    static var monthYear: DateFormatter {
        cachedDateFormatter(key: "monthYear") { $0.dateFormat = "MMMM yyyy" }
    }

    static var shortMonthDay: DateFormatter {
        cachedDateFormatter(key: "shortMonthDay") { $0.dateFormat = "MMM d" }
    }

    static var shortDayDate: DateFormatter {
        cachedDateFormatter(key: "shortDayDate") { $0.dateFormat = "EEE, MMM d" }
    }

    static var dayOfWeek: DateFormatter {
        cachedDateFormatter(key: "dayOfWeek") { $0.dateFormat = "EEEE" }
    }

    static var shortDayOfWeek: DateFormatter {
        cachedDateFormatter(key: "shortDayOfWeek") { $0.dateFormat = "EEE" }
    }

    static var dayNumber: DateFormatter {
        cachedDateFormatter(key: "dayNumber") { $0.dateFormat = "d" }
    }

    static var shortTime: DateFormatter {
        cachedDateFormatter(key: "shortTime") {
            $0.dateStyle = .none
            $0.timeStyle = .short
        }
    }

    static var mediumDateTime: DateFormatter {
        cachedDateFormatter(key: "mediumDateTime") {
            $0.dateStyle = .medium
            $0.timeStyle = .short
        }
    }

    static var fullDateTime: DateFormatter {
        cachedDateFormatter(key: "fullDateTime") { $0.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a" }
    }

    static var iso8601DateTime: DateFormatter {
        cachedDateFormatter(key: "iso8601DateTime") {
            $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        }
    }

    static var time24HourWithSeconds: DateFormatter {
        cachedDateFormatter(key: "time24HourWithSeconds") { $0.dateFormat = "HH:mm:ss" }
    }

    static var iso8601: ISO8601DateFormatter {
        cachedISO8601Formatter(key: "iso8601") { $0.formatOptions = [.withFullDate] }
    }
}
