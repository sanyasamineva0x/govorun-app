import Foundation
import SwiftData

// MARK: - HistoryStore

final class HistoryStore {
    static let maxItems = 100

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ result: PipelineResult, appContext: AppContext) throws {
        let text = result.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let wordCount = text.split(whereSeparator: \.isWhitespace).count

        let item = HistoryItem(
            sessionId: result.sessionId,
            rawTranscript: result.rawTranscript,
            normalizedText: result.normalizedText,
            textMode: result.superStyle?.rawValue ?? "none",
            appName: appContext.appName.isEmpty ? nil : appContext.appName,
            normalizationPath: result.normalizationPath.rawValue,
            sttLatencyMs: result.sttLatencyMs,
            normalizationLatencyMs: result.llmLatencyMs,
            insertionLatencyMs: result.insertionLatencyMs,
            totalLatencyMs: result.totalLatencyMs,
            wordCount: wordCount,
            insertionStrategy: result.insertionStrategy?.rawValue,
            audioFileName: result.audioFileName
        )

        modelContext.insert(item)
        try enforceMaxItems()
    }

    func recent(limit: Int = 10) throws -> [HistoryItem] {
        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func clear() throws {
        let all = try modelContext.fetch(FetchDescriptor<HistoryItem>())
        for item in all {
            if let fileName = item.audioFileName {
                AudioHistoryStorage.deleteFile(named: fileName)
            }
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    // MARK: - Private

    private func enforceMaxItems() throws {
        let count = try modelContext.fetchCount(FetchDescriptor<HistoryItem>())
        let excess = count - Self.maxItems
        guard excess > 0 else {
            try modelContext.save()
            return
        }

        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = excess
        let oldest = try modelContext.fetch(descriptor)
        for item in oldest {
            if let fileName = item.audioFileName {
                AudioHistoryStorage.deleteFile(named: fileName)
            }
            modelContext.delete(item)
        }
        try modelContext.save()
    }
}
