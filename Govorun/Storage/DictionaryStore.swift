import Foundation
import SwiftData

// MARK: - Ошибки

enum DictionaryStoreError: Error {
    case wordNotFound(String)
    case saveFailed(underlying: Error)
}

// MARK: - DictionaryStore

final class DictionaryStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func addWord(_ word: String, alternatives: [String]) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Проверяем дубликат — если слово существует, мержим alternatives
        if let existing = try findEntry(for: trimmed) {
            let newAlts = alternatives.filter { !existing.alternatives.contains($0) }
            existing.alternatives.append(contentsOf: newAlts)
            try save()
            return
        }

        let entry = DictionaryEntry(word: trimmed, alternatives: alternatives)
        modelContext.insert(entry)
        try save()
    }

    func removeWord(_ word: String) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = try findEntry(for: trimmed) else {
            throw DictionaryStoreError.wordNotFound(trimmed)
        }
        modelContext.delete(entry)
        try save()
    }

    func allEntries() throws -> [DictionaryEntry] {
        let descriptor = FetchDescriptor<DictionaryEntry>(
            sortBy: [SortDescriptor(\.word)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Форматы для pipeline

    /// Хинты для STT — все слова из словаря
    func sttHints() throws -> [String] {
        let entries = try allEntries()
        return entries.map(\.word)
    }

    /// Замены для LLM промпта — alternative → word
    func llmReplacements() throws -> [String: String] {
        let entries = try allEntries()
        var replacements: [String: String] = [:]
        for entry in entries {
            for alt in entry.alternatives {
                replacements[alt] = entry.word
            }
        }
        return replacements
    }

    // MARK: - Пост-замены после ASR

    /// Заменить alternatives на правильное слово в тексте.
    /// Case-insensitive, целые слова (word boundary).
    /// Применяется к rawTranscript ПЕРЕД DeterministicNormalizer.
    func applyReplacements(to text: String) throws -> String {
        let entries = try allEntries()
        return Self.applyReplacements(to: text, entries: entries)
    }

    /// Статический вариант для использования без SwiftData (в Pipeline через personalDictionary)
    static func applyReplacements(to text: String, replacements: [String: String]) -> String {
        guard !text.isEmpty, !replacements.isEmpty else { return text }
        var result = text
        for (pattern, replacement) in replacements {
            guard !pattern.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Внутренняя версия для entries из базы
    static func applyReplacements(to text: String, entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }
        var result = text
        for entry in entries {
            for alt in entry.alternatives {
                guard !alt.isEmpty else { continue }
                let escaped = NSRegularExpression.escapedPattern(for: alt)
                result = result.replacingOccurrences(
                    of: "\\b\(escaped)\\b",
                    with: entry.word,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }
        return result
    }

    // MARK: - Private

    private func findEntry(for word: String) throws -> DictionaryEntry? {
        let descriptor = FetchDescriptor<DictionaryEntry>(
            predicate: #Predicate { $0.word == word }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.saveFailed(underlying: error)
        }
    }
}
