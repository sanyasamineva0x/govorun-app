import Foundation
import SwiftData

// MARK: - Результаты агрегации

struct LatencyPercentiles {
    let p50: Int
    let p90: Int
    let p95: Int
}

/// Читает аналитические события для построения дашборда.
/// ModelContext из AppModelContainer.shared — analytics в отдельной конфигурации.
struct MetricsAggregator {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - §6.1 Zero-Edit Rate

    /// Доля успешных вставок без правок и undo за 60s окно.
    func zeroEditRate(from: Date, to: Date) throws -> Double? {
        let succeeded = try sessionsWithEvent(.insertionSucceeded, from: from, to: to)
        guard !succeeded.isEmpty else { return nil }

        let edited = try sessionsWithEvent(.manualEditDetected, from: from, to: to)
        let undone = try sessionsWithEvent(.undoDetected, from: from, to: to)
        let badSessions = edited.union(undone)

        let clean = succeeded.subtracting(badSessions).count
        return Double(clean)/Double(succeeded.count)
    }

    // MARK: - §6.3 Insertion Success Rate

    /// Доля попыток вставки, завершившихся успехом.
    func insertionSuccessRate(from: Date, to: Date) throws -> Double? {
        let started = try sessionsWithEvent(.insertionStarted, from: from, to: to)
        guard !started.isEmpty else { return nil }

        let succeeded = try sessionsWithEvent(.insertionSucceeded, from: from, to: to)
        let successInWindow = started.intersection(succeeded).count
        return Double(successInWindow)/Double(started.count)
    }

    // MARK: - §6.4 Median End-to-End Latency

    /// Перцентили e2e латенси (p50, p90, p95) из metadata insertion_succeeded событий.
    func latencyPercentiles(from: Date, to: Date) throws -> LatencyPercentiles? {
        let events = try fetchEvents(type: .insertionSucceeded, from: from, to: to)
        let latencies = events.compactMap { event -> Int? in
            guard let str = event.metadata[AnalyticsMetadataKey.e2eLatencyMs] else { return nil }
            return Int(str)
        }.sorted()

        guard !latencies.isEmpty else { return nil }

        return LatencyPercentiles(
            p50: percentile(latencies, p: 50),
            p90: percentile(latencies, p: 90),
            p95: percentile(latencies, p: 95)
        )
    }

    // MARK: - §6.5 Undo Rate

    /// Доля успешных вставок, после которых был undo.
    func undoRate(from: Date, to: Date) throws -> Double? {
        let succeeded = try sessionsWithEvent(.insertionSucceeded, from: from, to: to)
        guard !succeeded.isEmpty else { return nil }

        let undone = try sessionsWithEvent(.undoDetected, from: from, to: to)
        let undoneInWindow = succeeded.intersection(undone).count
        return Double(undoneInWindow)/Double(succeeded.count)
    }

    // MARK: - §6.6 Retry Rate

    /// Доля сессий, за которыми в течение 30s следует новая диктовка.
    func retryRate(from: Date, to: Date) throws -> Double? {
        let starts = try fetchEvents(type: .dictationStarted, from: from, to: to)
            .sorted { $0.timestamp < $1.timestamp }

        guard starts.count >= 2 else {
            return starts.isEmpty ? nil : 0.0
        }

        var retries = 0
        for i in 0..<(starts.count - 1) {
            let gap = starts[i + 1].timestamp.timeIntervalSince(starts[i].timestamp)
            if gap <= 30.0 {
                retries += 1
            }
        }
        return Double(retries)/Double(starts.count)
    }

    // MARK: - Fallback Rate

    /// Доля сессий, где использовался clipboard fallback (AX insertion не сработал).
    func clipboardFallbackRate(from: Date, to: Date) throws -> Double? {
        let succeeded = try sessionsWithEvent(.insertionSucceeded, from: from, to: to)
        guard !succeeded.isEmpty else { return nil }

        let fallbacks = try sessionsWithEvent(.clipboardFallbackUsed, from: from, to: to)
        let fallbackInWindow = succeeded.intersection(fallbacks).count
        return Double(fallbackInWindow)/Double(succeeded.count)
    }

    // MARK: - Private

    private func fetchEvents(type: AnalyticsEventName, from: Date, to: Date) throws -> [AnalyticsEvent] {
        let typeName = type.rawValue
        let predicate = #Predicate<AnalyticsEvent> {
            $0.type == typeName && $0.timestamp >= from && $0.timestamp <= to
        }
        let descriptor = FetchDescriptor<AnalyticsEvent>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    private func sessionsWithEvent(_ type: AnalyticsEventName, from: Date, to: Date) throws -> Set<UUID> {
        let events = try fetchEvents(type: type, from: from, to: to)
        return Set(events.compactMap(\.sessionId))
    }

    /// Nearest-rank percentile
    private func percentile(_ sorted: [Int], p: Int) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let rank = Double(p)/100.0 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return Int(Double(sorted[lower]) * (1.0 - fraction) + Double(sorted[upper]) * fraction)
    }
}
