import SwiftUI

struct BlockProposalCardView: View {
    let data: BlockProposalCardData
    let onAction: ((ChatButtonAction) -> Void)?

    @State private var editingProposalId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label("Day Plan", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(data.dateLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(data.rationale)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()

            // Proposal rows
            ForEach(data.proposals) { proposal in
                proposalRow(proposal)
            }

            // Bottom buttons
            buttonRow(data.buttons)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func proposalRow(_ proposal: BlockProposalCardData.ProposalViewData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(themeColor(proposal.themeColor))
                    .frame(width: 8, height: 8)

                Text(proposal.themeName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .strikethrough(proposal.status == .skipped)
                    .foregroundColor(proposal.status == .skipped ? .secondary : .primary)

                Spacer()

                Text("\(proposal.startLabel) – \(proposal.endLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                statusBadge(proposal.status)
            }

            if !proposal.taskTitles.isEmpty && proposal.status != .skipped {
                Text(proposal.taskTitles.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let notes = proposal.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }

            if proposal.status == .pending || proposal.status == .edited {
                HStack(spacing: 6) {
                    Button {
                        onAction?(.confirmProposal(draftId: data.draftId, proposalId: proposal.id))
                    } label: {
                        Label("Confirm", systemImage: "checkmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.green)

                    Button {
                        onAction?(.skipProposal(draftId: data.draftId, proposalId: proposal.id))
                    } label: {
                        Label("Skip", systemImage: "forward")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button {
                        editingProposalId = editingProposalId == proposal.id ? nil : proposal.id
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .popover(isPresented: Binding(
                        get: { editingProposalId == proposal.id },
                        set: { if !$0 { editingProposalId = nil } }
                    )) {
                        ProposalTimeEditor(
                            proposal: proposal,
                            draftId: data.draftId,
                            onAction: onAction,
                            onDismiss: { editingProposalId = nil }
                        )
                    }
                }
            }
        }
        .padding(8)
        .background(proposalBackground(proposal.status))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func statusBadge(_ status: BlockProposalCardData.ProposalStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .confirmed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .skipped:
            Image(systemName: "forward.circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        case .edited:
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        }
    }

    private func proposalBackground(_ status: BlockProposalCardData.ProposalStatus) -> Color {
        switch status {
        case .pending:
            return Color(NSColor.controlBackgroundColor)
        case .confirmed:
            return Color.green.opacity(0.08)
        case .skipped:
            return Color(NSColor.controlBackgroundColor).opacity(0.5)
        case .edited:
            return Color.orange.opacity(0.08)
        }
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
                proposalButton(button)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func proposalButton(_ button: ChatActionButton) -> some View {
        if button.style == .primary {
            Button(button.title) {
                onAction?(button.action)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(button.isDisabled || onAction == nil)
        } else {
            Button(button.title) {
                onAction?(button.action)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(button.isDisabled || onAction == nil)
        }
    }
}

// MARK: - Time Editor Popover

struct ProposalTimeEditor: View {
    let proposal: BlockProposalCardData.ProposalViewData
    let draftId: String
    let onAction: ((ChatButtonAction) -> Void)?
    let onDismiss: () -> Void

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String

    init(
        proposal: BlockProposalCardData.ProposalViewData,
        draftId: String,
        onAction: ((ChatButtonAction) -> Void)?,
        onDismiss: @escaping () -> Void
    ) {
        self.proposal = proposal
        self.draftId = draftId
        self.onAction = onAction
        self.onDismiss = onDismiss

        let start = SharedDateFormatters.iso8601DateTime.date(from: proposal.startISO) ?? Date()
        let end = SharedDateFormatters.iso8601DateTime.date(from: proposal.endISO) ?? Date()
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
        _notes = State(initialValue: proposal.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit \(proposal.themeName)")
                .font(.callout)
                .fontWeight(.medium)

            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                .font(.caption)
            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                .font(.caption)

            TextField("Notes", text: $notes)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Apply") {
                    let startISO = SharedDateFormatters.iso8601DateTime.string(from: startTime)
                    let endISO = SharedDateFormatters.iso8601DateTime.string(from: endTime)
                    onAction?(.editProposalTime(draftId: draftId, proposalId: proposal.id, newStartISO: startISO, newEndISO: endISO))
                    if !notes.isEmpty {
                        onAction?(.updateProposalNotes(draftId: draftId, proposalId: proposal.id, notes: notes))
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
