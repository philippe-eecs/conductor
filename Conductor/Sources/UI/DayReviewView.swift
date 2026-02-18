import SwiftUI

struct DayReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: DayReviewSnapshot?
    @State private var draft: PlanningDraft?
    @State private var isLoading = true
    @State private var isApplyingDraft = false
    @State private var publishResult: PublishPlanResult?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView("Preparing day review...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else if let snapshot {
                        todaySection(snapshot)
                        themeFocusSection(snapshot)
                        weekSection(snapshot)
                        emailSection(snapshot)
                        draftSection
                    } else {
                        Text("Unable to load day review.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 460, height: 620)
        .task {
            await refresh()
            DayReviewService.shared.markShownToday()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Day Review")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(SharedDateFormatters.fullDateNoYear.string(from: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func todaySection(_ snapshot: DayReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "sun.max")
                .font(.subheadline)
                .fontWeight(.semibold)

            if snapshot.todayEvents.isEmpty {
                Text("No calendar events today")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshot.todayEvents.prefix(6), id: \.id) { event in
                    HStack {
                        Text(event.time)
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text(event.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(event.duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let activeTheme = snapshot.activeTheme {
                HStack(spacing: 8) {
                    Circle().fill(activeTheme.swiftUIColor).frame(width: 8, height: 8)
                    Text("Active theme: \(activeTheme.name)")
                        .font(.callout)
                    Spacer()
                }
                if let objective = activeTheme.objective, !objective.isEmpty {
                    Text(objective)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func themeFocusSection(_ snapshot: DayReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Theme Focus", systemImage: "target")
                .font(.subheadline)
                .fontWeight(.semibold)

            if snapshot.todayThemeBuckets.isEmpty {
                Text("No theme-linked tasks due today.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshot.todayThemeBuckets) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(bucket.theme.swiftUIColor).frame(width: 8, height: 8)
                            Text(bucket.theme.name).font(.callout).fontWeight(.medium)
                            Spacer()
                            Text("\(bucket.tasks.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let objective = bucket.theme.objective, !objective.isEmpty {
                            Text(objective)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        ForEach(bucket.tasks.prefix(3)) { task in
                            Text("- \(task.title)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }

            if !snapshot.looseTasks.isEmpty {
                Text("Loose tasks: \(snapshot.looseTasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func weekSection(_ snapshot: DayReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This Week", systemImage: "calendar")
                .font(.subheadline)
                .fontWeight(.semibold)

            if snapshot.weekSummaries.isEmpty {
                Text("No theme commitments due this week.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshot.weekSummaries) { summary in
                    HStack {
                        Text(summary.themeName)
                            .font(.callout)
                        Spacer()
                        if summary.highPriorityCount > 0 {
                            Text("\(summary.highPriorityCount) high")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text("\(summary.openCount) open")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func emailSection(_ snapshot: DayReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Important Emails", systemImage: "envelope.badge")
                .font(.subheadline)
                .fontWeight(.semibold)

            if snapshot.actionNeededEmails.isEmpty {
                Text("No action-needed emails.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshot.actionNeededEmails.prefix(5)) { email in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email.subject)
                            .font(.callout)
                            .lineLimit(1)
                        Text(email.sender)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Plan Draft", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Generate") {
                    Task {
                        draft = await PlanningDraftService.shared.planDay()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let draft {
                if draft.proposals.isEmpty {
                    Text("No draft blocks suggested.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(draft.proposals) { proposal in
                        HStack {
                            Circle().fill(proposal.theme.swiftUIColor).frame(width: 8, height: 8)
                            Text(proposal.theme.name)
                                .font(.callout)
                            Spacer()
                            Text("\(SharedDateFormatters.time12Hour.string(from: proposal.startTime)) - \(SharedDateFormatters.time12Hour.string(from: proposal.endTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Button("Apply Draft") {
                            Task {
                                isApplyingDraft = true
                                _ = try? PlanningDraftService.shared.applyDraft(draft)
                                isApplyingDraft = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplyingDraft)

                        Button("Publish Today's Planned Blocks") {
                            Task {
                                let plannedToday = ((try? Database.shared.getThemeBlocksForDay(Date())) ?? [])
                                    .filter { $0.status == .planned }
                                    .map(\.id)
                                publishResult = await PlanningDraftService.shared.publishThemeBlocks(plannedToday)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let publishResult {
                        Text("Published: \(publishResult.publishedBlockIds.count), Failed: \(publishResult.failedBlockIds.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Generate a draft to get theme-based time-block suggestions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func refresh() async {
        isLoading = true
        snapshot = await DayReviewService.shared.buildSnapshot()
        isLoading = false
    }
}
