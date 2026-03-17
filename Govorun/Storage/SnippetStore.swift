import Foundation
import SwiftData

// MARK: - Ошибки SnippetStore

enum SnippetStoreError: Error {
    case snippetNotFound(String)
}

// MARK: - SnippetStore

final class SnippetStore {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func addSnippet(
        trigger: String,
        content: String,
        matchMode: MatchMode = .fuzzy
    ) throws {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Дубликат триггера → обновить content
        let existing = try findByTrigger(trimmed)
        if let existing {
            existing.content = content
            existing.matchMode = matchMode
        } else {
            let snippet = Snippet(trigger: trimmed, content: content, matchMode: matchMode)
            modelContext.insert(snippet)
        }

        try modelContext.save()
    }

    func removeSnippet(trigger: String) throws {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let snippet = try findByTrigger(trimmed) else {
            throw SnippetStoreError.snippetNotFound(trimmed)
        }

        modelContext.delete(snippet)
        try modelContext.save()
    }

    func setEnabled(_ enabled: Bool, for trigger: String) throws {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let snippet = try findByTrigger(trimmed) else {
            throw SnippetStoreError.snippetNotFound(trimmed)
        }

        snippet.isEnabled = enabled
        try modelContext.save()
    }

    func allSnippets() throws -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(
            sortBy: [SortDescriptor(\.trigger)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Конвертирует все сниппеты в SnippetRecord для SnippetEngine
    func snippetRecords() throws -> [SnippetRecord] {
        let all = try allSnippets()
        return all.map { snippet in
            SnippetRecord(
                trigger: snippet.trigger,
                content: snippet.content,
                matchMode: snippet.matchMode,
                isEnabled: snippet.isEnabled
            )
        }
    }

    func seedDefaultsIfNeeded() throws {
        guard (try allSnippets()).isEmpty else { return }

        let defaults: [(String, String, MatchMode)] = [
            ("мой имейл", "example@email.com", .fuzzy),
            ("мой телефон", "+7 (999) 000-00-00", .fuzzy),
            ("адрес офиса", "г. Москва, ул. Примерная, д. 1", .fuzzy),
        ]

        for (trigger, content, mode) in defaults {
            try addSnippet(trigger: trigger, content: content, matchMode: mode)
        }
    }

    func incrementUsage(trigger: String) throws {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let snippet = try findByTrigger(trimmed) else {
            throw SnippetStoreError.snippetNotFound(trimmed)
        }

        snippet.usageCount += 1
        try modelContext.save()
    }

    // MARK: - Private

    // SwiftData #Predicate не поддерживает .lowercased() — in-memory фильтрация.
    // При типичных 5-50 сниппетах производительность не проблема.
    private func findByTrigger(_ trigger: String) throws -> Snippet? {
        let lowered = trigger.lowercased()
        let all = try modelContext.fetch(FetchDescriptor<Snippet>())
        return all.first { $0.trigger.lowercased() == lowered }
    }
}
