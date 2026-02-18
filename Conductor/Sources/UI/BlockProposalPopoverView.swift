import SwiftUI

struct BlockProposalPopoverView: View {
    let draftId: String
    let message: ChatMessage
    let onAction: ((ChatButtonAction) -> Void)?
    let onDismiss: () -> Void

    private var blockProposalData: BlockProposalCardData? {
        for element in message.uiElements {
            if case .blockProposal(let data) = element, data.draftId == draftId {
                return data
            }
        }
        return nil
    }

    private var calendarData: CompactWeekCalendarData? {
        for element in message.uiElements {
            if case .compactWeekCalendar(let data) = element, data.draftId == draftId {
                return data
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Day Plan — \(blockProposalData?.dateLabel ?? "")")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Calendar at larger scale
                    if let calData = calendarData {
                        CompactWeekCalendarView(data: calData, onAction: onAction)
                    }

                    // All proposal cards
                    if let proposalData = blockProposalData {
                        BlockProposalCardView(data: proposalData, onAction: onAction)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}
