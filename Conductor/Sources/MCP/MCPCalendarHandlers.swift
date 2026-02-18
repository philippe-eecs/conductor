import Foundation

// MARK: - Calendar, Reminders, Goals, Notes, Emails

extension MCPToolHandlers {

    func handleGetCalendar(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "calendar_read_enabled")) != "false" else {
            return mcpError("Calendar access is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        guard EventKitManager.shared.calendarAuthorizationStatus() == .fullAccess else {
            return mcpError("Calendar permission not granted. The user needs to grant Full Access in System Settings > Privacy & Security > Calendars.")
        }

        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        if let startStr = args["start_date"] as? String, let parsed = parseDate(startStr) {
            startDate = calendar.startOfDay(for: parsed)
        } else {
            startDate = calendar.startOfDay(for: now)
        }

        let endDate: Date
        if let endStr = args["end_date"] as? String, let parsed = parseDate(endStr) {
            endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: parsed)) ?? parsed
        } else {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }

        let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        guard daysBetween <= Self.maxDateRangeDays else {
            return mcpError("Date range too large. Maximum is \(Self.maxDateRangeDays) days.")
        }

        let events = await EventKitManager.shared.getEvents(from: startDate, to: endDate)
        let capped = Array(events.prefix(Self.maxItemsPerCall))

        let text: String
        if capped.isEmpty {
            let dateDesc = SharedDateFormatters.fullDate.string(from: startDate)
            text = "No calendar events found for \(dateDesc)."
        } else {
            let lines = capped.map { event -> String in
                var line = "- \(event.time): \(event.title) (\(event.duration))"
                if let location = event.location, !location.isEmpty {
                    line += " @ \(location)"
                }
                return line
            }
            text = "Found \(capped.count) event(s):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    func handleGetReminders(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "reminders_read_enabled")) != "false" else {
            return mcpError("Reminders access is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        guard EventKitManager.shared.remindersAuthorizationStatus() == .fullAccess else {
            return mcpError("Reminders permission not granted. The user needs to grant Full Access in System Settings > Privacy & Security > Reminders.")
        }

        let limit = min(args["limit"] as? Int ?? 20, Self.maxItemsPerCall)
        let reminders = await EventKitManager.shared.getUpcomingReminders(limit: limit)

        let text: String
        if reminders.isEmpty {
            text = "No pending reminders found."
        } else {
            let lines = reminders.map { r -> String in
                var line = "- \(r.title)"
                if let due = r.dueDate {
                    line += " (due: \(due))"
                }
                if r.priority > 0 {
                    line += " [priority: \(r.priority)]"
                }
                return line
            }
            text = "Found \(reminders.count) reminder(s):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    func handleGetGoals(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else {
            return mcpError("Daily planning is disabled in Conductor Settings. The user can enable it in Settings > Daily Planning.")
        }

        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let completionRate = (try? Database.shared.getGoalCompletionRate(forDays: 7)) ?? 0
        let overdueGoals = (try? Database.shared.getIncompleteGoals(before: today)) ?? []

        let text: String
        if goals.isEmpty && overdueGoals.isEmpty {
            text = "No goals set for today and no overdue goals."
        } else {
            var lines: [String] = []

            if !goals.isEmpty {
                lines.append("Today's goals:")
                for goal in goals {
                    let status = goal.isCompleted ? "[done]" : "[pending]"
                    lines.append("- \(status) \(goal.goalText) (priority: \(goal.priority))")
                }
            }

            if !overdueGoals.isEmpty {
                lines.append("\nOverdue goals (\(overdueGoals.count)):")
                for goal in overdueGoals.prefix(10) {
                    lines.append("- \(goal.goalText) (from \(goal.date))")
                }
            }

            lines.append("\n7-day completion rate: \(Int(completionRate * 100))%")

            text = lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    func handleGetNotes(_ args: [String: Any]) async -> [String: Any] {
        let limit = min(args["limit"] as? Int ?? 5, Self.maxItemsPerCall)

        guard let notes = try? Database.shared.loadNotes(limit: limit), !notes.isEmpty else {
            return mcpSuccess("No notes found.")
        }

        let lines = notes.map { note -> String in
            let preview = String(note.content.prefix(200))
            return "- \(note.title): \(preview)"
        }
        let text = "Found \(notes.count) note(s):\n" + lines.joined(separator: "\n")

        return mcpSuccess(text)
    }

    func handleGetEmails(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true" else {
            return mcpError("Email integration is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        let emailContext = await MailService.shared.buildEmailContext()
        let filter = args["filter"] as? String

        var emails = emailContext.importantEmails
        if let filter, !filter.isEmpty {
            emails = emails.filter { email in
                email.sender.localizedCaseInsensitiveContains(filter) ||
                email.subject.localizedCaseInsensitiveContains(filter)
            }
        }

        let capped = Array(emails.prefix(Self.maxItemsPerCall))

        let text: String
        if capped.isEmpty {
            text = filter != nil
                ? "No emails matching '\(filter!)' found."
                : "No important emails found. Unread count: \(emailContext.unreadCount)."
        } else {
            let lines = capped.map { email -> String in
                let readStatus = email.isRead ? "" : " (unread)"
                return "- From \(email.sender): \(email.subject)\(readStatus)"
            }
            text = "Unread: \(emailContext.unreadCount). Important emails (\(capped.count)):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }
}
