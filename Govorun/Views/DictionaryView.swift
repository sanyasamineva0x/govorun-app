import SwiftData
import SwiftUI

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryEntry.word) private var entries: [DictionaryEntry]

    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var filteredEntries: [DictionaryEntry] {
        if searchText.isEmpty {
            return entries
        }
        let query = searchText.lowercased()
        return entries.filter {
            $0.word.lowercased().contains(query) ||
                $0.alternatives.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toolbar
            HStack(spacing: 8) {
                SettingsSearchBar(text: $searchText)

                if !entries.isEmpty {
                    CountBadge(count: entries.count)
                }

                AddButton(help: "Добавить слово") {
                    showingAddSheet = true
                }
            }

            // Список
            if filteredEntries.isEmpty {
                BrandedEmptyState(
                    icon: "character.book.closed",
                    title: entries.isEmpty
                        ? "Словарь пока пуст"
                        : "Ничего не найдено",
                    subtitle: entries.isEmpty
                        ? "Добавьте слова, которые я слышу неправильно"
                        : nil,
                    actionTitle: entries.isEmpty ? "Добавить слово" : nil,
                    action: entries.isEmpty ? { showingAddSheet = true } : nil
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        DictionaryRowView(entry: entry, onDelete: {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        })
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWordSheet()
        }
    }
}

// MARK: - Строка словаря

private struct DictionaryRowView: View {
    let entry: DictionaryEntry
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.word)
                    .font(.body.weight(.medium))
                if !entry.alternatives.isEmpty {
                    Text(entry.alternatives.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Удалить")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.primary.opacity(isHovered ? 0.04 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Добавление слова

private struct AddWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var word = ""
    @State private var alternativesText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Добавить слово")
                .font(.headline)

            TextField("Слово (как пишется)", text: $word)
                .textFieldStyle(.roundedBorder)

            TextField("Варианты произношения (через запятую)", text: $alternativesText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Добавить") { addWord() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func addWord() {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let alternatives = alternativesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let store = DictionaryStore(modelContext: modelContext)
        try? store.addWord(trimmed, alternatives: alternatives)
        dismiss()
    }
}
