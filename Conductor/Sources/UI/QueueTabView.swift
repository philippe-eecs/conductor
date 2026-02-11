import SwiftUI
import AppKit

struct QueueTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var schedulerState: SchedulerState = .init()
    @State private var meetingWarnings: [SchedulerState.MeetingWarning] = []
    @State private var agentTasks: [AgentTask] = []
    @State private var recentResults: [AgentTaskResult] = []

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !appState.pendingActions.isEmpty {
                        pendingApprovalsSection
                    }
                    agentTasksSection
                    recentResultsSection
                    nextEventSection
                    todaysJobsSection
                    meetingWarningsSection
                }
                .padding(12)
            }
        }
        .onAppear { refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var header: some View {
        HStack {
            Text("Queue")
                .font(.headline)
            Spacer()
            Button("Refresh") { refresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Pending Approvals

    private var pendingApprovalsSection: some View {
        ActionApprovalView(
            actions: appState.pendingActions,
            onApprove: { appState.approveAction($0) },
            onReject: { appState.rejectAction($0) },
            onApproveAll: { appState.approveAllActions() }
        )
    }

    // MARK: - Agent Tasks

    private var agentTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Tasks")
                .font(.caption)
                .foregroundColor(.secondary)

            if agentTasks.isEmpty {
                Text("No active agent tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(agentTasks) { task in
                        agentTaskRow(task)
                    }
                }
            }
        }
    }

    private func agentTaskRow(_ task: AgentTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForTrigger(task.triggerType))
                .foregroundColor(colorForStatus(task.status))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(task.triggerType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                    if let nextRun = task.nextRun {
                        Text("Next: \(SharedDateFormatters.time12Hour.string(from: nextRun))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if task.runCount > 0 {
                        Text("Runs: \(task.runCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button("Run") {
                AgentTaskScheduler.shared.triggerTask(id: task.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Recent Results

    private var recentResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Agent Results")
                .font(.caption)
                .foregroundColor(.secondary)

            if recentResults.isEmpty {
                Text("No recent results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentResults) { result in
                        resultRow(result)
                    }
                }
            }
        }
    }

    private func resultRow(_ result: AgentTaskResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: result.status == .success ? "checkmark.circle" : result.status == .failed ? "xmark.circle" : "clock")
                    .foregroundColor(result.status == .success ? .green : result.status == .failed ? .red : .orange)
                    .font(.caption)
                Text(SharedDateFormatters.time12Hour.string(from: result.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let cost = result.costUsd {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            Text(String(result.output.prefix(150)))
                .font(.caption)
                .lineLimit(3)
                .foregroundColor(.primary)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Scheduler State

    private var nextEventSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next")
                .font(.caption)
                .foregroundColor(.secondary)

            if let next = schedulerState.nextEvent {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: next.category == .meetingWarning ? "bell.badge" : "clock")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.description)
                            .font(.callout)
                            .lineLimit(2)
                        Text("\(next.formattedTime) • in \(next.timeUntil)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Text("Nothing scheduled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }

    private var todaysJobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Check-ins")
                .font(.caption)
                .foregroundColor(.secondary)

            if schedulerState.todaysJobs.isEmpty {
                Text("No daily jobs configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(schedulerState.todaysJobs.sorted(by: { ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture) })) { job in
                        jobRow(job)
                    }
                }
            }
        }
    }

    private func jobRow(_ job: SchedulerState.JobStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(job.isCompleted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.callout)
                    .lineLimit(1)
                if let time = job.scheduledTime {
                    Text("\(job.formattedTime) • \(job.formattedDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(SharedDateFormatters.fullDateTime.string(from: time))
                }
            }

            Spacer()

            Button("Run") {
                _ = EventScheduler.shared.runJobNow(id: job.id, force: true)
                refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }

    private var meetingWarningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meeting Warnings")
                .font(.caption)
                .foregroundColor(.secondary)

            if meetingWarnings.isEmpty {
                Text("No upcoming warnings (or Calendar access not granted).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(meetingWarnings) { warning in
                        HStack(spacing: 10) {
                            Image(systemName: "bell")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.eventTitle)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text("\(warning.formattedEventTime) • \(warning.minutesBefore)m before")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func refresh() {
        schedulerState = EventScheduler.shared.getSchedulerState()
        meetingWarnings = EventScheduler.shared.getTodayMeetingWarnings()
        agentTasks = (try? Database.shared.getActiveAgentTasks()) ?? []
        recentResults = (try? Database.shared.getRecentAgentTaskResults(limit: 5)) ?? []
    }

    private func iconForTrigger(_ trigger: AgentTask.TriggerType) -> String {
        switch trigger {
        case .time: return "clock"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .event: return "bell.badge"
        case .checkin: return "person.wave.2"
        case .manual: return "hand.tap"
        }
    }

    private func colorForStatus(_ status: AgentTask.Status) -> Color {
        switch status {
        case .active: return .green
        case .paused: return .orange
        case .completed: return .secondary
        case .expired: return .red
        }
    }
}

#Preview {
    QueueTabView()
        .environmentObject(AppState.shared)
        .frame(width: 400, height: 500)
}
