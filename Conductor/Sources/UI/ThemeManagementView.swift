import SwiftUI

struct ThemeManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var themes: [Theme] = []
    @State private var showNewTheme = false
    @State private var editingTheme: Theme?
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Themes")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("Archived", isOn: $showArchived)
                    .toggleStyle(.button)
                    .controlSize(.small)
                Button(action: { showNewTheme = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if themes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No themes yet")
                        .foregroundColor(.secondary)
                    Text("Themes group related tasks, goals, and notes\nto help you focus on what matters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create Theme") { showNewTheme = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(themes) { theme in
                        ThemeRowView(theme: theme, onEdit: {
                            editingTheme = theme
                        }, onArchive: {
                            Task {
                                try? Database.shared.archiveTheme(id: theme.id)
                                await loadThemes()
                            }
                        }, onDelete: {
                            Task {
                                try? Database.shared.deleteTheme(id: theme.id)
                                await loadThemes()
                            }
                        })
                    }
                }
            }
        }
        .frame(width: 400, height: 400)
        .task { await loadThemes() }
        .onChange(of: showArchived) { _, _ in
            Task { await loadThemes() }
        }
        .sheet(isPresented: $showNewTheme) {
            ThemeEditSheet(onSave: { theme in
                Task {
                    try? Database.shared.createTheme(theme)
                    await loadThemes()
                }
            })
        }
        .sheet(item: $editingTheme) { theme in
            ThemeEditSheet(theme: theme, onSave: { updated in
                Task {
                    try? Database.shared.updateTheme(updated)
                    await loadThemes()
                }
            })
        }
    }

    private func loadThemes() async {
        themes = (try? Database.shared.getThemes(includeArchived: showArchived)) ?? []
    }
}

// MARK: - Theme Row

struct ThemeRowView: View {
    let theme: Theme
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var taskCount: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(theme.swiftUIColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if theme.isArchived {
                        Text("archived")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                if let desc = theme.themeDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit") { onEdit() }
            Button(theme.isArchived ? "Unarchive" : "Archive") { onArchive() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .task {
            taskCount = (try? Database.shared.getTaskCountForTheme(id: theme.id)) ?? 0
        }
    }
}

// MARK: - Theme Edit Sheet

struct ThemeEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var description: String
    @State private var keywords: [String]
    @State private var newKeyword: String = ""

    private let isEditing: Bool
    private let themeId: String
    let onSave: (Theme) -> Void

    private let colors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"]

    init(theme: Theme? = nil, onSave: @escaping (Theme) -> Void) {
        self.isEditing = theme != nil
        self.themeId = theme?.id ?? UUID().uuidString
        _name = State(initialValue: theme?.name ?? "")
        _selectedColor = State(initialValue: theme?.color ?? "blue")
        _description = State(initialValue: theme?.themeDescription ?? "")
        _keywords = State(initialValue: [])
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Theme" : "New Theme")
                .font(.headline)

            TextField("Theme name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)

            // Color picker
            HStack {
                Text("Color")
                    .foregroundColor(.secondary)
                Spacer()
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(colorFor(color))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture { selectedColor = color }
                }
            }

            // Calendar keywords
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar keywords")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Events matching these keywords will be grouped under this theme.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("Add keyword...", text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addKeyword() }
                    Button("Add") { addKeyword() }
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !keywords.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(keywords, id: \.self) { kw in
                            HStack(spacing: 2) {
                                Text(kw)
                                    .font(.caption)
                                Button(action: { removeKeyword(kw) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(isEditing ? "Save" : "Create") {
                    let theme = Theme(
                        id: themeId,
                        name: name,
                        color: selectedColor,
                        themeDescription: description.isEmpty ? nil : description
                    )
                    onSave(theme)

                    // Save keywords
                    if isEditing {
                        // Clear old keywords and re-add
                        let oldKeywords = (try? Database.shared.getThemeKeywords(forTheme: themeId)) ?? []
                        for kw in oldKeywords {
                            try? Database.shared.removeThemeKeyword(kw, fromTheme: themeId)
                        }
                    }
                    for kw in keywords {
                        try? Database.shared.addThemeKeyword(kw, toTheme: themeId)
                    }

                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
        .task {
            if isEditing {
                keywords = (try? Database.shared.getThemeKeywords(forTheme: themeId)) ?? []
            }
        }
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !kw.isEmpty, !keywords.contains(kw) else { return }
        keywords.append(kw)
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        keywords.removeAll { $0 == kw }
    }

    private func colorFor(_ name: String) -> Color {
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
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
