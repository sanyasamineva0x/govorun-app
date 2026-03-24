@testable import Govorun
import SwiftData
import XCTest

final class MetricsAggregatorTests: XCTestCase {
    private var context: ModelContext!
    private var aggregator: MetricsAggregator!

    private let windowStart = Date(timeIntervalSince1970: 0)
    private let windowEnd = Date(timeIntervalSince1970: 10_000)

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: AnalyticsEvent.self,
            configurations: config
        )
        context = ModelContext(container)
        aggregator = MetricsAggregator(modelContext: context)
    }

    private func insertEvent(
        _ type: AnalyticsEventName,
        sessionId: UUID? = nil,
        timestamp: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        let event = AnalyticsEvent(
            type: type.rawValue,
            timestamp: timestamp ?? Date(timeIntervalSince1970: 100),
            sessionId: sessionId,
            metadata: metadata
        )
        context.insert(event)
        try! context.save()
    }

    // MARK: - Zero-Edit Rate

    func test_zero_edit_rate_all_clean() throws {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s3)

        let rate = try aggregator.zeroEditRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 1.0)
    }

    func test_zero_edit_rate_with_edits() throws {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s3)
        insertEvent(.manualEditDetected, sessionId: s1) // одна правка

        let rate = try aggregator.zeroEditRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 2.0/3.0, accuracy: 0.001)
    }

    func test_zero_edit_rate_undo_counts_as_bad() throws {
        let s1 = UUID(), s2 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)
        insertEvent(.undoDetected, sessionId: s2) // undo

        let rate = try aggregator.zeroEditRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 0.5, accuracy: 0.001)
    }

    func test_zero_edit_rate_empty_returns_nil() throws {
        let rate = try aggregator.zeroEditRate(from: windowStart, to: windowEnd)
        XCTAssertNil(rate)
    }

    // MARK: - Insertion Success Rate

    func test_insertion_success_rate_all_succeed() throws {
        let s1 = UUID(), s2 = UUID()
        insertEvent(.insertionStarted, sessionId: s1)
        insertEvent(.insertionStarted, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)

        let rate = try aggregator.insertionSuccessRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 1.0)
    }

    func test_insertion_success_rate_some_fail() throws {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        insertEvent(.insertionStarted, sessionId: s1)
        insertEvent(.insertionStarted, sessionId: s2)
        insertEvent(.insertionStarted, sessionId: s3)
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionFailed, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s3)

        let rate = try aggregator.insertionSuccessRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 2.0/3.0, accuracy: 0.001)
    }

    func test_insertion_success_rate_empty_returns_nil() throws {
        let rate = try aggregator.insertionSuccessRate(from: windowStart, to: windowEnd)
        XCTAssertNil(rate)
    }

    // MARK: - Latency Percentiles

    func test_latency_percentiles_basic() throws {
        // 10 событий с e2e_latency = 100, 200, ..., 1000
        for i in 1...10 {
            let sessionId = UUID()
            insertEvent(.insertionSucceeded, sessionId: sessionId, metadata: [
                AnalyticsMetadataKey.e2eLatencyMs: "\(i * 100)",
            ])
        }

        let result = try aggregator.latencyPercentiles(from: windowStart, to: windowEnd)
        XCTAssertNotNil(result)

        // p50 sorted: [100,200,...,1000], index 4.5 → interpolation between 500 and 600
        XCTAssertEqual(result?.p50, 550)
    }

    func test_latency_percentiles_empty_returns_nil() throws {
        let result = try aggregator.latencyPercentiles(from: windowStart, to: windowEnd)
        XCTAssertNil(result)
    }

    func test_latency_percentiles_single_event() throws {
        insertEvent(.insertionSucceeded, sessionId: UUID(), metadata: [
            AnalyticsMetadataKey.e2eLatencyMs: "300",
        ])

        let result = try aggregator.latencyPercentiles(from: windowStart, to: windowEnd)
        XCTAssertEqual(result?.p50, 300)
        XCTAssertEqual(result?.p90, 300)
        XCTAssertEqual(result?.p95, 300)
    }

    // MARK: - Undo Rate

    func test_undo_rate() throws {
        let s1 = UUID(), s2 = UUID(), s3 = UUID(), s4 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s3)
        insertEvent(.insertionSucceeded, sessionId: s4)
        insertEvent(.undoDetected, sessionId: s2)

        let rate = try aggregator.undoRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 0.25, accuracy: 0.001)
    }

    func test_undo_rate_no_undos() throws {
        let s1 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)

        let rate = try aggregator.undoRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 0.0)
    }

    // MARK: - Retry Rate

    func test_retry_rate_with_retries() throws {
        // 3 dictation_started: gap 10s (retry), gap 60s (not retry)
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 100))
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 110)) // 10s → retry
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 200)) // 90s → not retry

        let rate = try aggregator.retryRate(from: windowStart, to: windowEnd)
        // 1 retry из 3 starts
        XCTAssertEqual(try XCTUnwrap(rate), 1.0/3.0, accuracy: 0.001)
    }

    func test_retry_rate_no_retries() throws {
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 100))
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 200))

        let rate = try aggregator.retryRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 0.0)
    }

    func test_retry_rate_single_session() throws {
        insertEvent(.dictationStarted)

        let rate = try aggregator.retryRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 0.0)
    }

    func test_retry_rate_empty_returns_nil() throws {
        let rate = try aggregator.retryRate(from: windowStart, to: windowEnd)
        XCTAssertNil(rate)
    }

    func test_retry_rate_boundary_30s() throws {
        // Ровно 30 секунд = retry
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 100))
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 130)) // 30s → retry
        insertEvent(.dictationStarted, timestamp: Date(timeIntervalSince1970: 161)) // 31s → not retry

        let rate = try aggregator.retryRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 1.0/3.0, accuracy: 0.001)
    }

    // MARK: - Fallback Rate

    func test_clipboard_fallback_rate() throws {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        insertEvent(.insertionSucceeded, sessionId: s1)
        insertEvent(.insertionSucceeded, sessionId: s2)
        insertEvent(.insertionSucceeded, sessionId: s3)
        insertEvent(.clipboardFallbackUsed, sessionId: s1)

        let rate = try aggregator.clipboardFallbackRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(try XCTUnwrap(rate), 1.0/3.0, accuracy: 0.001)
    }

    func test_clipboard_fallback_rate_no_fallbacks() throws {
        insertEvent(.insertionSucceeded, sessionId: UUID())

        let rate = try aggregator.clipboardFallbackRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 0.0)
    }

    // MARK: - Date window filtering

    func test_events_outside_window_excluded() throws {
        let insideSession = UUID()
        let outsideSession = UUID()

        insertEvent(.insertionSucceeded, sessionId: insideSession, timestamp: Date(timeIntervalSince1970: 500))
        insertEvent(.insertionSucceeded, sessionId: outsideSession, timestamp: Date(timeIntervalSince1970: 20_000))

        let rate = try aggregator.zeroEditRate(from: windowStart, to: windowEnd)
        XCTAssertEqual(rate, 1.0) // Только 1 событие в окне
    }

    // MARK: - Percentile через latencyPercentiles (5 чётных значений)

    func test_latency_percentiles_five_values() throws {
        // [100, 200, 300, 400, 500] → p50=300, p90=460, p95=480
        for latency in [100, 200, 300, 400, 500] {
            insertEvent(.insertionSucceeded, sessionId: UUID(), metadata: [
                AnalyticsMetadataKey.e2eLatencyMs: "\(latency)",
            ])
        }

        let result = try aggregator.latencyPercentiles(from: windowStart, to: windowEnd)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.p50, 300)
    }
}
