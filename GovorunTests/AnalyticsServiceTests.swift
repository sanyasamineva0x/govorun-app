import XCTest
import SwiftData
@testable import Govorun

final class AnalyticsServiceTests: XCTestCase {

    private func makeService() throws -> (AnalyticsService, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AnalyticsEvent.self,
            configurations: config
        )
        let service = AnalyticsService(modelContainer: container)
        return (service, container)
    }

    private func fetchAll(_ container: ModelContainer) throws -> [AnalyticsEvent] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<AnalyticsEvent>())
    }

    // MARK: - Запись событий

    func test_emit_writes_event_to_swiftdata() async throws {
        let (service, container) = try makeService()
        let sessionId = UUID()

        await service.emit(.dictationStarted, sessionId: sessionId, metadata: [
            AnalyticsMetadataKey.appBundleId: "com.test.app"
        ])

        let events = try fetchAll(container)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, "dictation_started")
        XCTAssertEqual(events[0].sessionId, sessionId)
        XCTAssertEqual(events[0].metadata[AnalyticsMetadataKey.appBundleId], "com.test.app")
    }

    func test_emit_multiple_events_preserves_all() async throws {
        let (service, container) = try makeService()
        let sessionId = UUID()

        await service.emit(.dictationStarted, sessionId: sessionId, metadata: [:])
        await service.emit(.sttCompleted, sessionId: sessionId, metadata: [:])
        await service.emit(.insertionSucceeded, sessionId: sessionId, metadata: [:])

        let events = try fetchAll(container)
        XCTAssertEqual(events.count, 3)

        let types = Set(events.map(\.type))
        XCTAssertTrue(types.contains("dictation_started"))
        XCTAssertTrue(types.contains("stt_completed"))
        XCTAssertTrue(types.contains("insertion_succeeded"))
    }

    func test_emit_without_session_id() async throws {
        let (service, container) = try makeService()

        await service.emit(.dictationCancelled, sessionId: nil, metadata: [:])

        let events = try fetchAll(container)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0].sessionId)
    }

    // MARK: - Metadata serialization

    func test_metadata_round_trips() async throws {
        let (service, container) = try makeService()
        let metadata: [String: String] = [
            AnalyticsMetadataKey.sttLatencyMs: "150",
            AnalyticsMetadataKey.normalizationPath: "llm",
            AnalyticsMetadataKey.insertionStrategy: "ax_selected_text",
            AnalyticsMetadataKey.e2eLatencyMs: "500"
        ]

        await service.emit(.insertionSucceeded, sessionId: UUID(), metadata: metadata)

        let events = try fetchAll(container)
        XCTAssertEqual(events[0].metadata[AnalyticsMetadataKey.sttLatencyMs], "150")
        XCTAssertEqual(events[0].metadata[AnalyticsMetadataKey.normalizationPath], "llm")
        XCTAssertEqual(events[0].metadata[AnalyticsMetadataKey.insertionStrategy], "ax_selected_text")
    }

    // MARK: - Auto-prune

    func test_auto_prune_removes_oldest_events() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AnalyticsEvent.self,
            configurations: config
        )

        // Предварительно заполняем до лимита
        let prefillContext = ModelContext(container)
        for i in 0..<AnalyticsService.maxEvents {
            let event = AnalyticsEvent(
                type: "prefill",
                timestamp: Date(timeIntervalSince1970: TimeInterval(i)),
                sessionId: nil,
                metadata: ["index": "\(i)"]
            )
            prefillContext.insert(event)
        }
        try prefillContext.save()

        let service = AnalyticsService(modelContainer: container)

        // Добавляем ещё 5 событий
        for i in 0..<5 {
            await service.emit(.dictationStarted, sessionId: nil, metadata: ["extra": "\(i)"])
        }

        let allEvents = try fetchAll(container)
        XCTAssertEqual(allEvents.count, AnalyticsService.maxEvents)

        // Самые новые (extra) должны остаться
        let extraEvents = allEvents.filter { $0.metadata["extra"] != nil }
        XCTAssertEqual(extraEvents.count, 5)
    }

    // MARK: - Timestamp

    func test_timestamp_is_set_automatically() async throws {
        let (service, container) = try makeService()
        let before = Date()

        await service.emit(.dictationStarted, sessionId: nil, metadata: [:])

        let after = Date()
        let events = try fetchAll(container)
        XCTAssertEqual(events.count, 1)
        XCTAssertGreaterThanOrEqual(events[0].timestamp, before)
        XCTAssertLessThanOrEqual(events[0].timestamp, after)
    }

    // MARK: - Shared container

    func test_analytics_works_with_shared_container() async throws {
        // AnalyticsService использует общий контейнер (как в production)
        let (service, container) = try makeService()

        await service.emit(.dictationStarted, sessionId: UUID(), metadata: [:])
        await service.emit(.sttCompleted, sessionId: UUID(), metadata: [:])

        let events = try fetchAll(container)
        XCTAssertEqual(events.count, 2)
    }
}
