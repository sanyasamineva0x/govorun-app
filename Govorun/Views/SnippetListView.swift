import SwiftData
import SwiftUI

extension Notification.Name {
    static let snippetsDidChange = Notification.Name("GovorunSnippetsDidChange")
}

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.trigger) private var snippets: [Snippet]

    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return snippets
        }
        let query = searchText.lowercased()
        return snippets.filter {
            $0.trigger.lowercased().contains(query) ||
                $0.content.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toolbar
            HStack(spacing: 8) {
                SettingsSearchBar(text: $searchText)

                if !snippets.isEmpty {
                    CountBadge(count: snippets.count)
                }

                AddButton(help: "Добавить команду") {
                    showingAddSheet = true
                }
            }

            // Список
            if filteredSnippets.isEmpty {
                BrandedEmptyState(
                    icon: "text.bubble",
                    title: snippets.isEmpty
                        ? "Команд пока нет"
                        : "Ничего не найдено",
                    subtitle: snippets.isEmpty
                        ? "Добавьте голосовые команды\nдля быстрой вставки текста"
                        : nil,
                    actionTitle: snippets.isEmpty ? "Добавить команду" : nil,
                    action: snippets.isEmpty ? { showingAddSheet = true } : nil
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(filteredSnippets) { snippet in
                        SnippetRowView(snippet: snippet)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSnippetSheet()
        }
    }
}

// MARK: - Строка сниппета

private struct SnippetRowView: View {
    @Bindable var snippet: Snippet
    @Environment(\.modelContext) private var modelContext

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.trigger)
                        .font(.body.weight(.medium))

                    Text(snippet.matchMode == .fuzzy ? "нечёткий" : "точный")
                        .font(.caption2)
                        .foregroundStyle(snippet.matchMode == .fuzzy ? Color.sage : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (snippet.matchMode == .fuzzy ? Color.sage : .secondary)
                                .opacity(0.1)
                        )
                        .clipShape(Capsule())
                }

                Text(snippet.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    Button(action: {
                        snippet.isEnabled.toggle()
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
                    }) {
                        Image(systemName: snippet.isEnabled ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(snippet.isEnabled ? Color.sage : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(snippet.isEnabled ? "Выключить" : "Включить")

                    Button(action: {
                        modelContext.delete(snippet)
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Удалить")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(snippet.isEnabled ? 1 : 0.5)
        .background(.primary.opacity(isHovered ? 0.04 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Toggle("Включён", isOn: Binding(
                get: { snippet.isEnabled },
                set: { newValue in
                    snippet.isEnabled = newValue
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
                }
            ))
        }
    }
}

// MARK: - Добавление сниппета

private struct AddSnippetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var trigger = ""
    @State private var content = ""
    @State private var matchMode: MatchMode = .fuzzy

    var body: some View {
        VStack(spacing: 16) {
            Text("Добавить команду")
                .font(.headline)

            TextField("Триггер (что сказать)", text: $trigger)
                .textFieldStyle(.roundedBorder)

            TextField("Текст (что вставить)", text: $content)
                .textFieldStyle(.roundedBorder)

            Picker("Режим", selection: $matchMode) {
                Text("Нечёткий").tag(MatchMode.fuzzy)
                Text("Точный").tag(MatchMode.exact)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Добавить") { addSnippet() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func addSnippet() {
        let store = SnippetStore(modelContext: modelContext)
        try? store.addSnippet(
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            matchMode: matchMode
        )
        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
        dismiss()
    }
}
