import Foundation

struct PromptPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let template: String
    let hint: String?
}

enum PromptPresets {
    static let all: [PromptPreset] = [
        PromptPreset(
            id: "capture",
            title: "Capture",
            template: "Capture the following into actionable tasks, with due dates if implied. Ask 1 clarifying question only if needed.\n\n",
            hint: "Turn a brain-dump into TODOs."
        ),
        PromptPreset(
            id: "schedule",
            title: "Schedule",
            template: "Find time on my calendar for this and propose 2–3 options with tradeoffs:\n\n",
            hint: "Block time, propose options."
        ),
        PromptPreset(
            id: "daily_plan",
            title: "Daily Plan",
            template: "Given my schedule and tasks, propose a realistic plan for today with time blocks and a top-3 priority list.\n\n",
            hint: "Plan the day."
        ),
        PromptPreset(
            id: "weekly_plan",
            title: "Weekly Plan",
            template: "Help me plan the next 7 days: identify busy days, suggest focus blocks, and pick 3 outcomes to aim for.\n\n",
            hint: "Plan the week."
        ),
        PromptPreset(
            id: "triage",
            title: "Triage",
            template: "Triage and prioritize. Output:\n- Top 5\n- What to defer\n- What to delegate\n- Next actions\n\nContext:\n",
            hint: "Prioritize and decide."
        ),
    ]
}

