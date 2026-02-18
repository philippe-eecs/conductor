import Foundation
import os

struct ThemeSuggestion {
    let theme: Theme?
    let confidence: Double
    let reason: String
}

@MainActor
final class ThemeService {
    static let shared = ThemeService()

    private init() {}

    func ensureLooseTheme() -> Theme {
        (try? Database.shared.getLooseTheme()) ?? Theme(name: "Loose", color: "gray", themeDescription: "Unassigned tasks", isLooseBucket: true)
    }

    func suggestTheme(for text: String) -> ThemeSuggestion {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ThemeSuggestion(theme: nil, confidence: 0, reason: "Empty input")
        }

        let themes = ((try? Database.shared.getThemes()) ?? []).filter { !$0.isLooseBucket }
        guard !themes.isEmpty else {
            return ThemeSuggestion(theme: nil, confidence: 0, reason: "No themes available")
        }

        var bestTheme: Theme?
        var bestScore = 0.0
        var bestReason = ""

        for theme in themes {
            var score = 0.0
            var reasons: [String] = []

            let themeName = theme.name.lowercased()
            if normalized.contains(themeName) {
                score += 0.8
                reasons.append("matches theme name")
            }

            if let objective = theme.objective?.lowercased(), !objective.isEmpty {
                let objectiveWords = Set(objective.split(separator: " ").map(String.init))
                let inputWords = Set(normalized.split(separator: " ").map(String.init))
                let overlap = inputWords.intersection(objectiveWords).count
                if overlap > 0 {
                    score += min(0.4, Double(overlap) * 0.12)
                    reasons.append("overlaps objective")
                }
            }

            let keywords = (try? Database.shared.getThemeKeywords(forTheme: theme.id)) ?? []
            let keywordHits = keywords.filter { keyword in
                normalized.contains(keyword.lowercased())
            }
            if !keywordHits.isEmpty {
                score += min(0.6, Double(keywordHits.count) * 0.2)
                reasons.append("keyword hit")
            }

            let taskCount = (try? Database.shared.getTaskCountForTheme(id: theme.id)) ?? 0
            if taskCount > 0 {
                score += min(0.15, Double(taskCount) * 0.01)
            }

            if score > bestScore {
                bestScore = score
                bestTheme = theme
                bestReason = reasons.joined(separator: ", ")
            }
        }

        if bestScore < 0.35 {
            return ThemeSuggestion(theme: nil, confidence: bestScore, reason: "No strong thematic match")
        }

        return ThemeSuggestion(theme: bestTheme, confidence: min(1.0, bestScore), reason: bestReason.isEmpty ? "Best lexical match" : bestReason)
    }

    func assignTask(_ taskId: String, toThemeId themeId: String?) {
        let targetThemeId: String
        if let themeId {
            targetThemeId = themeId
        } else {
            targetThemeId = ensureLooseTheme().id
        }

        do {
            let existingThemes = try Database.shared.getThemesForItem(itemType: .task, itemId: taskId)
            for existing in existingThemes {
                try Database.shared.removeItemFromTheme(themeId: existing.id, itemType: .task, itemId: taskId)
            }
            try Database.shared.addItemToTheme(themeId: targetThemeId, itemType: .task, itemId: taskId)
        } catch {
            Log.database.error("Failed to assign task \(taskId, privacy: .public) to theme \(targetThemeId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func resolveTheme(
        themeId explicitThemeId: String?,
        themeName explicitThemeName: String?,
        createIfMissing: Bool = true,
        color: String = "blue"
    ) -> Theme? {
        if let explicitThemeId,
           !explicitThemeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try? Database.shared.getTheme(id: explicitThemeId)
        }

        if let explicitThemeName {
            let trimmed = explicitThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.caseInsensitiveCompare("loose") == .orderedSame {
                return ensureLooseTheme()
            }

            let existing = ((try? Database.shared.getThemes(includeArchived: false)) ?? [])
                .first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            if let existing {
                return existing
            }

            if createIfMissing {
                let theme = Theme(name: trimmed, color: color, objective: "High-level objective for \(trimmed)")
                do {
                    try Database.shared.createTheme(theme)
                    return (try? Database.shared.getTheme(id: theme.id)) ?? theme
                } catch {
                    Log.database.error("Failed to create theme '\(trimmed, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    return theme
                }
            }
            return nil
        }

        return ensureLooseTheme()
    }

    func tasksForTheme(_ themeId: String, includeCompleted: Bool = false) -> [TodoTask] {
        let ids = (try? Database.shared.getTaskIdsForTheme(id: themeId)) ?? []
        guard !ids.isEmpty else { return [] }

        let allTasks = (try? Database.shared.getAllTasks(includeCompleted: includeCompleted)) ?? []
        let set = Set(ids)
        return allTasks.filter { set.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.priority.rawValue != rhs.priority.rawValue {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                let lDue = lhs.dueDate ?? .distantFuture
                let rDue = rhs.dueDate ?? .distantFuture
                return lDue < rDue
            }
    }

    func activeTheme(at date: Date = Date()) -> Theme? {
        try? Database.shared.getActiveTheme(at: date)
    }
}
