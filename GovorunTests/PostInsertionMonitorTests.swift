@testable import Govorun
import XCTest

// MARK: - Mocks

final class MockFocusedTextReader: FocusedTextReading {
    var textToReturn: String?
    func readFocusedText() -> String? {
        textToReturn
    }
}

final class MockFrontmostAppProvider: FrontmostAppProviding {
    var bundleIdToReturn: String?
    private var activationHandler: (() -> Void)?

    func frontmostBundleId() -> String? {
        bundleIdToReturn
    }

    func addActivationObserver(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        activationHandler = handler
        return NSString(string: "mock_observer")
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        activationHandler = nil
    }

    func simulateAppSwitch(to bundleId: String) {
        bundleIdToReturn = bundleId
        activationHandler?()
    }
}

final class MockGlobalKeyMonitorProvider: GlobalKeyMonitorProviding {
    private var keyHandler: ((GlobalKeyEvent) -> Void)?

    func addGlobalKeyDownMonitor(handler: @escaping (GlobalKeyEvent) -> Void) -> Any? {
        keyHandler = handler
        return "mock_key_monitor"
    }

    func removeMonitor(_ monitor: Any) {
        keyHandler = nil
    }

    func simulateKeyDown(keyCode: UInt16, modifiers: GlobalKeyEvent.ModifierFlags) {
        let event = GlobalKeyEvent(keyCode: keyCode, modifierFlags: modifiers)
        keyHandler?(event)
    }
}

final class MockAnalyticsCollector: AnalyticsEmitting, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(AnalyticsEventName, UUID?, [String: String])] = []

    var events: [(AnalyticsEventName, UUID?, [String: String])] {
        lock.withLock { _events }
    }

    func emit(_ event: AnalyticsEventName, sessionId: UUID?, metadata: [String: String]) async {
        lock.withLock { _events.append((event, sessionId, metadata)) }
    }

    func hasEvent(_ name: AnalyticsEventName) -> Bool {
        events.contains { $0.0 == name }
    }
}

// MARK: - Tests

@MainActor
final class PostInsertionMonitorTests: XCTestCase {
    private var textReader: MockFocusedTextReader!
    private var appProvider: MockFrontmostAppProvider!
    private var keyMonitor: MockGlobalKeyMonitorProvider!
    private var analytics: MockAnalyticsCollector!
    private var monitor: PostInsertionMonitor!

    override func setUp() {
        super.setUp()
        textReader = MockFocusedTextReader()
        appProvider = MockFrontmostAppProvider()
        keyMonitor = MockGlobalKeyMonitorProvider()
        analytics = MockAnalyticsCollector()
        monitor = PostInsertionMonitor(
            focusedTextReader: textReader,
            frontmostAppProvider: appProvider,
            eventMonitorProvider: keyMonitor
        )
    }

    override func tearDown() {
        monitor.stopMonitoring()
        super.tearDown()
    }

    /// Прокручиваем RunLoop чтобы Task {} внутри монитора успели выполниться
    private func drainMainQueue() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
    }

    // MARK: - 1. Текст не изменился → нет manual_edit_detected

    func test_no_edit_when_text_unchanged() {
        let sessionId = UUID()
        textReader.textToReturn = "Привет, мир."
        appProvider.bundleIdToReturn = "com.test.app"

        monitor.startMonitoring(
            sessionId: sessionId,
            insertedText: "Привет, мир.",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        XCTAssertFalse(analytics.hasEvent(.manualEditDetected))
    }

    // MARK: - 2. Cmd+Z в целевом приложении → undo_detected

    func test_cmd_z_in_target_app_emits_undo() {
        let sessionId = UUID()
        appProvider.bundleIdToReturn = "com.test.app"

        monitor.startMonitoring(
            sessionId: sessionId,
            insertedText: "Тест",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: .command)

        // callback обёрнут в Task { @MainActor }, нужно дать RunLoop прокрутиться
        let expectation = XCTestExpectation(description: "undo_detected emitted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.analytics.hasEvent(.undoDetected) {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)

        let undoEvents = analytics.events.filter { $0.0 == .undoDetected }
        XCTAssertEqual(undoEvents.count, 1)
        XCTAssertEqual(undoEvents[0].1, sessionId)
    }

    // MARK: - 3. Cmd+Z в другом приложении → игнорируется

    func test_cmd_z_in_other_app_ignored() {
        let sessionId = UUID()
        appProvider.bundleIdToReturn = "com.other.app"

        monitor.startMonitoring(
            sessionId: sessionId,
            insertedText: "Тест",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: .command)

        drainMainQueue()
        XCTAssertFalse(analytics.hasEvent(.undoDetected))
    }

    // MARK: - 4. Cmd+Shift+Z → не undo (это redo)

    func test_cmd_shift_z_is_not_undo() {
        appProvider.bundleIdToReturn = "com.test.app"

        monitor.startMonitoring(
            sessionId: UUID(),
            insertedText: "Тест",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        var flags = GlobalKeyEvent.ModifierFlags.command
        flags.insert(.shift)
        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: flags)

        drainMainQueue()
        XCTAssertFalse(analytics.hasEvent(.undoDetected))
    }

    // MARK: - 5. Переключение приложения → монитор останавливается

    func test_app_switch_stops_monitor() {
        appProvider.bundleIdToReturn = "com.test.app"

        monitor.startMonitoring(
            sessionId: UUID(),
            insertedText: "Тест",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        appProvider.simulateAppSwitch(to: "com.other.app")

        // app switch callback обёрнут в Task { @MainActor }
        drainMainQueue()

        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: .command)
        drainMainQueue()

        XCTAssertFalse(analytics.hasEvent(.undoDetected))
    }

    // MARK: - 6. Новая диктовка → предыдущий монитор cancel

    func test_new_dictation_cancels_previous_monitor() {
        appProvider.bundleIdToReturn = "com.test.app"
        let firstSessionId = UUID()
        let secondSessionId = UUID()

        monitor.startMonitoring(
            sessionId: firstSessionId,
            insertedText: "Первый",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        monitor.startMonitoring(
            sessionId: secondSessionId,
            insertedText: "Второй",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: .command)

        let expectation = XCTestExpectation(description: "undo emitted for second session")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let undos = self.analytics.events.filter { $0.0 == .undoDetected }
            if undos.count == 1, undos[0].1 == secondSessionId {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - 7. stopMonitoring очищает состояние

    func test_stop_monitoring_clears_state() {
        appProvider.bundleIdToReturn = "com.test.app"

        monitor.startMonitoring(
            sessionId: UUID(),
            insertedText: "Тест",
            targetBundleId: "com.test.app",
            analytics: analytics
        )

        monitor.stopMonitoring()

        keyMonitor.simulateKeyDown(keyCode: 6, modifiers: .command)

        drainMainQueue()
        XCTAssertTrue(analytics.events.isEmpty)
    }
}
