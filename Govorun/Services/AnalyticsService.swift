import Foundation
import SwiftData

// MARK: - AnalyticsService (actor)

//
// Аналитика пишется в отдельный SQLite файл (analytics.store)
// через отдельную ModelConfiguration в едином AppModelContainer.
// Actor изолирует все записи — thread-safe без deadlock.

actor AnalyticsService: AnalyticsEmitting {
    static let maxEvents = 10_000

    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    nonisolated func emit(_ event: AnalyticsEventName, sessionId: UUID?, metadata: [String: String]) async {
        await _emit(event, sessionId: sessionId, metadata: metadata)
    }

    // MARK: - Private

    private func _emit(_ event: AnalyticsEventName, sessionId: UUID?, metadata: [String: String]) {
        let analyticsEvent = AnalyticsEvent(
            type: event.rawValue,
            sessionId: sessionId,
            metadata: metadata
        )
        modelContext.insert(analyticsEvent)

        do {
            try modelContext.save()
            try enforceMaxEvents()
        } catch {
            print("[Govorun Analytics] Ошибка записи события \(event.rawValue): \(error)")
        }
    }

    private func enforceMaxEvents() throws {
        let count = try modelContext.fetchCount(FetchDescriptor<AnalyticsEvent>())
        let excess = count - Self.maxEvents
        guard excess > 0 else { return }

        var descriptor = FetchDescriptor<AnalyticsEvent>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = excess
        let oldest = try modelContext.fetch(descriptor)
        for event in oldest {
            modelContext.delete(event)
        }
        try modelContext.save()
    }
}
