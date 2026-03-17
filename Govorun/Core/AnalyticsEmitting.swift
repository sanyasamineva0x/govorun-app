import Foundation

// MARK: - Протокол аналитики (Core/ — чистый Swift)

protocol AnalyticsEmitting: Sendable {
    func emit(_ event: AnalyticsEventName, sessionId: UUID?, metadata: [String: String]) async
}

// MARK: - Заглушка (для тестов и случаев без аналитики)

final class NoOpAnalyticsService: AnalyticsEmitting, Sendable {
    func emit(_ event: AnalyticsEventName, sessionId: UUID?, metadata: [String: String]) async {}
}
