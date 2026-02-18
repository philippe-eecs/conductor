import SwiftUI

struct ChatUIElementsView: View {
    let elements: [ChatUIElement]
    let onAction: ((ChatButtonAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                elementView(element)
            }
        }
    }

    @ViewBuilder
    private func elementView(_ element: ChatUIElement) -> some View {
        switch element {
        case .nowContext(let data):
            nowContextCard(data)
        case .daySnapshot(let data):
            daySnapshotCard(data)
        case .slotPicker(let data):
            slotPickerCard(data)
        case .operationReceipt(let data):
            operationReceiptCard(data)
        case .weekSummary(let data):
            weekSummaryCard(data)
        case .themeDetail(let data):
            themeDetailCard(data)
        case .blockProposal(let data):
            BlockProposalCardView(data: data, onAction: onAction)
        case .compactWeekCalendar(let data):
            CompactWeekCalendarView(data: data, onAction: onAction)
        }
    }

    private func nowContextCard(_ data: NowContextCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Now", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(data.dateLabel)
                .font(.callout)
            Text("\(data.timeLabel) • \(data.timezoneLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Earliest suggested start: \(data.earliestStartLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            buttonRow(data.buttons)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func daySnapshotCard(_ data: DaySnapshotCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(data.title, systemImage: "sun.max")
                .font(.caption)
                .foregroundColor(.secondary)

            if let theme = data.activeThemeName {
                Text("Active theme: \(theme)")
                    .font(.callout)
                if let objective = data.activeThemeObjective, !objective.isEmpty {
                    Text(objective)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Theme tasks: \(data.openThemeTaskCount) • Loose tasks: \(data.looseTaskCount)")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(data.events.prefix(4)) { event in
                Text("• \(event.time)  \(event.title) (\(event.duration))")
                    .font(.caption)
                    .lineLimit(1)
            }

            buttonRow(data.buttons)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func slotPickerCard(_ data: SlotPickerCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(data.title, systemImage: "calendar.badge.clock")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(data.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if let hint = data.connectionHint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            ForEach(data.slots) { slot in
                Button {
                    onAction?(.selectSlot(slotId: slot.id))
                } label: {
                    HStack {
                        Text(slot.label)
                            .font(.callout)
                            .fontWeight(slot.isSelected ? .semibold : .regular)
                        Spacer()
                        Text(slot.reason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(slot.isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(slot.isDisabled || onAction == nil)
            }

            buttonRow(data.buttons)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func operationReceiptCard(_ data: OperationReceiptCardData) -> some View {
        let color: Color
        switch data.status {
        case .success:
            color = .green
        case .failed:
            color = .red
        case .partialSuccess:
            color = .orange
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: data.status == .failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(color)
                Text(data.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundColor(color)
                Spacer()
                Text(data.timestampLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(data.message)
                .font(.caption)

            Text("\(data.entityType)\(data.entityId.map { " • \($0)" } ?? "")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func weekSummaryCard(_ data: WeekSummaryCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(data.title, systemImage: "calendar")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(data.items.prefix(4)) { item in
                Text("• \(item.themeName): \(item.openCount) open, \(item.highPriorityCount) high")
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func themeDetailCard(_ data: ThemeDetailCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: color dot + theme name
            HStack(spacing: 6) {
                Circle()
                    .fill(themeColor(data.themeColor))
                    .frame(width: 10, height: 10)
                Text(data.themeName)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(data.openTaskCount) open, \(data.completedTaskCount) done")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Objective
            if let objective = data.objective, !objective.isEmpty {
                Text(objective)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Task list (up to 5)
            if !data.tasks.isEmpty {
                Divider()
                ForEach(data.tasks.prefix(5)) { task in
                    HStack(spacing: 6) {
                        Button {
                            onAction?(.completeTask(taskId: task.id))
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? .green : .secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .disabled(onAction == nil)

                        Text(task.title)
                            .font(.caption)
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer()

                        if let dueLabel = task.dueLabel {
                            Text(dueLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if data.openTaskCount > 5 {
                    Text("+\(data.openTaskCount - 5) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Upcoming blocks (up to 3)
            if !data.upcomingBlocks.isEmpty {
                Divider()
                Label("Upcoming", systemImage: "calendar")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(data.upcomingBlocks.prefix(3)) { block in
                    HStack(spacing: 4) {
                        if block.isRecurring {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(block.label)
                            .font(.caption)
                    }
                }
            }

            // View in Tasks button
            Button {
                onAction?(.viewThemeInSidebar(themeId: data.themeId))
            } label: {
                Text("View in Tasks")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(onAction == nil)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func themeColor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }

    private func buttonRow(_ buttons: [ChatActionButton]) -> some View {
        HStack(spacing: 6) {
            ForEach(buttons) { button in
                buttonView(button)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func buttonView(_ button: ChatActionButton) -> some View {
        switch button.style {
        case .primary:
            Button(button.title) {
                onAction?(button.action)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(button.isDisabled || onAction == nil)
            .help(button.hint ?? "")
        case .secondary:
            Button(button.title) {
                onAction?(button.action)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(button.isDisabled || onAction == nil)
            .help(button.hint ?? "")
        case .destructive:
            Button(button.title) {
                onAction?(button.action)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(button.isDisabled || onAction == nil)
            .help(button.hint ?? "")
        }
    }
}
