import SwiftUI

/// A time block for display in the timeline
struct TimeBlock: Identifiable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let color: Color
    let type: BlockType

    enum BlockType {
        case event
        case focusBlock
    }

    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
}

/// Compact horizontal timeline strip showing events as colored blocks
struct TimelineStrip: View {
    let events: [TimeBlock]
    let hours: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))

                // Hour markers (subtle dots)
                hourMarkers(width: geo.size.width)

                // Event blocks (colored rectangles)
                ForEach(events) { event in
                    eventBlock(event, totalWidth: geo.size.width)
                }

                // Now indicator (red line)
                nowIndicator(width: geo.size.width)
            }
        }
        .frame(height: 32)
    }

    private func hourMarkers(width: CGFloat) -> some View {
        let totalMinutes = CGFloat((hours.upperBound - hours.lowerBound) * 60)

        return ForEach(Array(hours), id: \.self) { hour in
            let minutesFromStart = CGFloat((hour - hours.lowerBound) * 60)
            let xOffset = (minutesFromStart / totalMinutes) * width

            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4, height: 4)
                .offset(x: xOffset - 2, y: 0)
        }
    }

    private func eventBlock(_ event: TimeBlock, totalWidth: CGFloat) -> some View {
        let totalMinutes = CGFloat((hours.upperBound - hours.lowerBound) * 60)
        let calendar = Calendar.current

        let eventStartMinutes = CGFloat(calendar.component(.hour, from: event.startTime) * 60 + calendar.component(.minute, from: event.startTime))
        let eventEndMinutes = CGFloat(calendar.component(.hour, from: event.endTime) * 60 + calendar.component(.minute, from: event.endTime))

        let startMinutesFromRange = eventStartMinutes - CGFloat(hours.lowerBound * 60)
        let endMinutesFromRange = eventEndMinutes - CGFloat(hours.lowerBound * 60)

        // Clamp to visible range
        let clampedStart = max(0, startMinutesFromRange)
        let clampedEnd = min(totalMinutes, endMinutesFromRange)

        guard clampedEnd > clampedStart else { return AnyView(EmptyView()) }

        let xOffset = (clampedStart / totalMinutes) * totalWidth
        let blockWidth = ((clampedEnd - clampedStart) / totalMinutes) * totalWidth

        return AnyView(
            RoundedRectangle(cornerRadius: 4)
                .fill(event.color.opacity(0.8))
                .frame(width: max(4, blockWidth), height: 24)
                .offset(x: xOffset, y: 0)
                .help(event.title)
        )
    }

    private func nowIndicator(width: CGFloat) -> some View {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Only show if current time is within range
        guard currentHour >= hours.lowerBound && currentHour <= hours.upperBound else {
            return AnyView(EmptyView())
        }

        let totalMinutes = CGFloat((hours.upperBound - hours.lowerBound) * 60)
        let nowMinutes = CGFloat(currentHour * 60 + calendar.component(.minute, from: now))
        let minutesFromStart = nowMinutes - CGFloat(hours.lowerBound * 60)
        let xOffset = (minutesFromStart / totalMinutes) * width

        return AnyView(
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: 32)
                .offset(x: xOffset - 1, y: 0)
        )
    }
}

#Preview {
    let calendar = Calendar.current
    let now = Date()
    let events = [
        TimeBlock(
            id: "1",
            title: "Team standup",
            startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
            color: .blue,
            type: .event
        ),
        TimeBlock(
            id: "2",
            title: "Focus: Project work",
            startTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!,
            color: .green,
            type: .focusBlock
        ),
        TimeBlock(
            id: "3",
            title: "Lunch",
            startTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
            color: .orange,
            type: .event
        )
    ]

    return VStack {
        TimelineStrip(events: events, hours: 8...20)
            .padding()
    }
    .frame(width: 350, height: 60)
}
