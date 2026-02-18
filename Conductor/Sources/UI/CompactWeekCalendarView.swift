import SwiftUI

struct CompactWeekCalendarView: View {
    let data: CompactWeekCalendarData
    let onAction: ((ChatButtonAction) -> Void)?

    private let startHour = 8
    private let endHour = 20
    private let hourHeight: CGFloat = 15
    private var totalHours: Int { endHour - startHour }
    private var gridHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Week Overview", systemImage: "calendar.day.timeline.left")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 0) {
                // Hour labels
                hourLabels

                // Day columns
                ForEach(data.days) { day in
                    dayColumn(day)
                }
            }
            .frame(height: gridHeight + 20) // +20 for day headers

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .accentColor.opacity(0.3), label: "Event", dashed: false)
                legendItem(color: .blue.opacity(0.25), label: "Proposed", dashed: true)
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private var hourLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Color.clear.frame(height: 20) // Header space

            ForEach(startHour..<endHour, id: \.self) { hour in
                Text(hourString(hour))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: hourHeight, alignment: .trailing)
            }
        }
    }

    private func dayColumn(_ day: CompactWeekCalendarData.DayColumn) -> some View {
        VStack(spacing: 0) {
            // Day header
            Text(day.dayLabel)
                .font(.system(size: 9, weight: day.isToday ? .bold : .regular))
                .foregroundColor(day.isToday ? .accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 20)

            // Time grid
            ZStack(alignment: .top) {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.08))
                            .frame(height: hourHeight)
                            .border(Color.secondary.opacity(0.05), width: 0.5)
                    }
                }

                // "Now" indicator
                if day.isToday {
                    nowIndicator
                }

                // Calendar events
                ForEach(day.events) { event in
                    eventBlock(event)
                }

                // Proposed blocks
                ForEach(day.proposedBlocks) { block in
                    proposedBlock(block)
                }
            }
            .frame(height: gridHeight)
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }

    private func eventBlock(_ event: CompactWeekCalendarData.EventSlot) -> some View {
        let yOffset = yPosition(minuteOfDay: event.startMinuteOfDay)
        let height = max(3, CGFloat(event.durationMinutes) / 60.0 * hourHeight)

        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor.opacity(0.3))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 1)
            .offset(y: yOffset)
            .frame(height: 0, alignment: .top)
    }

    private func proposedBlock(_ block: CompactWeekCalendarData.ProposedBlockSlot) -> some View {
        let yOffset = yPosition(minuteOfDay: block.startMinuteOfDay)
        let height = max(3, CGFloat(block.durationMinutes) / 60.0 * hourHeight)
        let color = blockThemeColor(block.themeColor)
        let isConfirmed = block.status == .confirmed
        let isSkipped = block.status == .skipped

        return RoundedRectangle(cornerRadius: 2)
            .fill(isSkipped ? Color.clear : color.opacity(isConfirmed ? 0.35 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isSkipped ? Color.secondary.opacity(0.2) : color.opacity(isConfirmed ? 0.6 : 0.4),
                        style: StrokeStyle(lineWidth: 1, dash: isConfirmed ? [] : [3, 2])
                    )
            )
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 1)
            .offset(y: yOffset)
            .frame(height: 0, alignment: .top)
            .opacity(isSkipped ? 0.3 : 1.0)
            .onTapGesture {
                if !isSkipped {
                    onAction?(.selectCalendarBlock(proposalId: block.id))
                }
            }
    }

    @ViewBuilder
    private var nowIndicator: some View {
        let calendar = Calendar.current
        let now = Date()
        let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let yOffset = yPosition(minuteOfDay: minuteOfDay)

        Rectangle()
            .fill(Color.red)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .offset(y: yOffset)
            .frame(height: 0, alignment: .top)
    }

    private func yPosition(minuteOfDay: Int) -> CGFloat {
        let minutesSinceStart = max(0, minuteOfDay - startHour * 60)
        return CGFloat(minutesSinceStart) / 60.0 * hourHeight
    }

    private func hourString(_ hour: Int) -> String {
        if hour == 12 { return "12p" }
        if hour < 12 { return "\(hour)a" }
        return "\(hour - 12)p"
    }

    private func blockThemeColor(_ name: String) -> Color {
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

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
                )
                .frame(width: 12, height: 8)
            Text(label)
        }
    }
}
