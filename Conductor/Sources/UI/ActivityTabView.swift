import SwiftUI

/// Shows recent activity log - what the app has done
/// Enhanced with filtering and detailed audit logging
struct ActivityTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFilter: ActivityFilter = .all
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Divider()

            // Activity list
            ScrollView {
                VStack(spacing: 8) {
                    if filteredActivity.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredActivity) { entry in
                            ActivityRowView(entry: entry)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(ActivityFilter.allCases) { filter in
                    Label(filter.label, systemImage: filter.icon)
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Spacer()

            // Entry count
            Text("\(filteredActivity.count) entries")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
    }

    // MARK: - Filtered Activity

    private var filteredActivity: [ActivityLogEntry] {
        var result = appState.recentActivity

        // Apply type filter
        if selectedFilter != .all {
            result = result.filter { $0.type == selectedFilter.activityType }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter { $0.message.lowercased().contains(searchLower) }
        }

        return result
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .all ? "clock.arrow.circlepath" : selectedFilter.icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            if selectedFilter == .all && searchText.isEmpty {
                Text("No activity yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text("Activity will appear here as you use Conductor")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No matching activity")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text("Try adjusting your filter or search")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Activity Filter

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case ai
    case scheduler
    case security
    case context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Activity"
        case .errors: return "Errors"
        case .ai: return "AI Responses"
        case .scheduler: return "Scheduler"
        case .security: return "Security"
        case .context: return "Context"
        }
    }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .errors: return "exclamationmark.triangle"
        case .ai: return "brain"
        case .scheduler: return "clock"
        case .security: return "lock.shield"
        case .context: return "doc.text"
        }
    }

    var activityType: ActivityLogEntry.ActivityType? {
        switch self {
        case .all: return nil
        case .errors: return .error
        case .ai: return .ai
        case .scheduler: return .scheduler
        case .security: return .security
        case .context: return .context
        }
    }
}

// MARK: - Activity Row View

struct ActivityRowView: View {
    let entry: ActivityLogEntry
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 10) {
                // Time
                Text(entry.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                // Icon
                Image(systemName: entry.type.icon)
                    .font(.caption)
                    .foregroundColor(entry.type.color)
                    .frame(width: 16)

                // Message
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                        .font(.callout)
                        .lineLimit(isExpanded ? nil : 2)

                    if let metadata = entry.metadata, !metadata.isEmpty {
                        if isExpanded {
                            metadataView(metadata)
                        } else {
                            Text("\(metadata.count) details")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Expand button for entries with metadata
                if entry.metadata != nil && !entry.metadata!.isEmpty {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .background(backgroundForType(entry.type))
        .cornerRadius(6)
    }

    private func metadataView(_ metadata: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(key)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(value)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.top, 4)
        .padding(.leading, 66)  // Align with message
    }

    private func backgroundForType(_ type: ActivityLogEntry.ActivityType) -> Color {
        switch type {
        case .error:
            return Color.red.opacity(0.1)
        case .scheduler:
            return Color.orange.opacity(0.1)
        case .security:
            return Color.purple.opacity(0.1)
        default:
            return Color(NSColor.controlBackgroundColor)
        }
    }
}

// MARK: - Group Activity by Date

struct ActivityDateGroup: Identifiable {
    let id = UUID()
    let date: String
    let entries: [ActivityLogEntry]

    var isToday: Bool {
        date == SharedDateFormatters.databaseDate.string(from: Date())
    }
}

extension Array where Element == ActivityLogEntry {
    func groupedByDate() -> [ActivityDateGroup] {
        let grouped = Dictionary(grouping: self) { entry in
            SharedDateFormatters.databaseDate.string(from: entry.timestamp)
        }

        return grouped.map { (date, entries) in
            ActivityDateGroup(date: date, entries: entries)
        }.sorted { $0.date > $1.date }
    }
}

#Preview {
    ActivityTabView()
        .environmentObject(AppState.shared)
        .frame(width: 400, height: 500)
}
