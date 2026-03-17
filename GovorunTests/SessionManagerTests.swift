import XCTest
@testable import Govorun

// MARK: - Мок EventMonitoring

final class MockEventMonitoring: EventMonitoring, @unchecked Sendable {
    private var flagsHandlers: [(Bool) -> Void] = []
    private var keyDownHandlers: [() -> Void] = []
    private(set) var removeMonitorCallCount = 0
    private var nextMonitorId = 0

    func addGlobalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any? {
        flagsHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addGlobalKeyDown(_ handler: @escaping () -> Void) -> Any? {
        keyDownHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addLocalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any? {
        flagsHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addLocalKeyDown(_ handler: @escaping () -> Void) -> Any? {
        keyDownHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func removeMonitor(_ monitor: Any) {
        removeMonitorCallCount += 1
    }

    // Симуляция событий
    func simulateOptionDown() {
        flagsHandlers.forEach { $0(true) }
    }

    func simulateOptionUp() {
        flagsHandlers.forEach { $0(false) }
    }

    func simulateKeyDown() {
        keyDownHandlers.forEach { $0() }
    }
}

// MARK: - Мок SessionManagerDelegate

@MainActor
final class MockSessionDelegate: SessionManagerDelegate {
    private(set) var stateChanges: [SessionState] = []

    func sessionManager(_ manager: SessionManager, didChangeState state: SessionState) {
        stateChanges.append(state)
    }
}

// MARK: - SessionManager тесты

@MainActor
final class SessionManagerTests: XCTestCase {

    // MARK: - 1. Начальное состояние idle

    func test_initial_state_idle() {
        let sut = SessionManager()
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - 2. activated → .recording

    func test_activated_transitions_to_recording() {
        let sut = SessionManager()
        sut.handleActivated()
        XCTAssertEqual(sut.state, .recording)
    }

    // MARK: - 3. deactivated → .processing

    func test_deactivated_transitions_to_processing() {
        let sut = SessionManager()
        sut.handleActivated()
        sut.handleDeactivated()
        XCTAssertEqual(sut.state, .processing)
    }

    // MARK: - 4. Esc/cancel → .idle

    func test_cancel_from_recording_transitions_to_idle() {
        let sut = SessionManager()
        sut.handleActivated()
        XCTAssertEqual(sut.state, .recording)

        sut.handleCancelled()
        XCTAssertEqual(sut.state, .idle)
    }

    func test_cancel_from_processing_transitions_to_idle() {
        let sut = SessionManager()
        sut.handleActivated()
        sut.handleDeactivated()
        XCTAssertEqual(sut.state, .processing)

        sut.handleCancelled()
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - 5. Полный цикл: idle → recording → processing → inserting → idle

    func test_full_cycle() {
        let sut = SessionManager()
        let delegate = MockSessionDelegate()
        sut.delegate = delegate

        sut.handleActivated()
        XCTAssertEqual(sut.state, .recording)

        sut.handleDeactivated()
        XCTAssertEqual(sut.state, .processing)

        sut.handleProcessingComplete()
        XCTAssertEqual(sut.state, .inserting)

        sut.handleInsertionComplete()
        XCTAssertEqual(sut.state, .idle)

        XCTAssertEqual(delegate.stateChanges, [.recording, .processing, .inserting, .idle])
    }

    // MARK: - 6. Error state

    func test_error_state() {
        let sut = SessionManager()
        sut.handleActivated()
        sut.handleDeactivated()

        sut.handleError("STT failed")
        XCTAssertEqual(sut.state, .error("STT failed"))

        sut.handleErrorDismissed()
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - 7. Невалидные переходы игнорируются

    func test_invalid_transitions_ignored() {
        let sut = SessionManager()

        // deactivated из idle → ничего
        sut.handleDeactivated()
        XCTAssertEqual(sut.state, .idle)

        // processingComplete из idle → ничего
        sut.handleProcessingComplete()
        XCTAssertEqual(sut.state, .idle)

        // insertionComplete из idle → ничего
        sut.handleInsertionComplete()
        XCTAssertEqual(sut.state, .idle)

        // activated из recording → ничего
        sut.handleActivated()
        XCTAssertEqual(sut.state, .recording)
        sut.handleActivated()
        XCTAssertEqual(sut.state, .recording)
    }

    // MARK: - 8. Delegate уведомляется

    func test_delegate_notified_on_state_change() {
        let sut = SessionManager()
        let delegate = MockSessionDelegate()
        sut.delegate = delegate

        sut.handleActivated()
        sut.handleCancelled()

        XCTAssertEqual(delegate.stateChanges, [.recording, .idle])
    }

    // MARK: - 9. Delegate не уведомляется при одинаковом состоянии

    func test_delegate_not_notified_on_same_state() {
        let sut = SessionManager()
        let delegate = MockSessionDelegate()
        sut.delegate = delegate

        sut.handleDeactivated() // idle → idle — ничего не произойдёт
        XCTAssertEqual(delegate.stateChanges, [])
    }
}

// MARK: - OptionKeyMonitor тесты

final class OptionKeyMonitorTests: XCTestCase {

    // MARK: - 10. 200ms hold → activated

    func test_option_hold_200ms_activates() {
        let mockEvents = MockEventMonitoring()
        let sut = OptionKeyMonitor(eventMonitor: mockEvents)

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mockEvents.simulateOptionDown()

        let expectation = expectation(description: "activated after 200ms")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(activated)
    }

    // MARK: - 11. Quick tap (< 200ms) → не активируется

    func test_quick_option_tap_ignored() {
        let mockEvents = MockEventMonitoring()
        let sut = OptionKeyMonitor(eventMonitor: mockEvents)

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mockEvents.simulateOptionDown()
        // Отпускаем быстро (< 200ms)
        mockEvents.simulateOptionUp()

        let expectation = expectation(description: "wait for timer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertFalse(activated)
    }

    // MARK: - 12. Option+key → cancelled

    func test_option_plus_key_cancels() {
        let mockEvents = MockEventMonitoring()
        let sut = OptionKeyMonitor(eventMonitor: mockEvents)

        var activated = false
        var cancelled = false
        sut.onActivated = { activated = true }
        sut.onCancelled = { cancelled = true }
        sut.startMonitoring()

        mockEvents.simulateOptionDown()
        // Нажимаем другую клавишу до 200ms
        mockEvents.simulateKeyDown()

        let expectation = expectation(description: "wait for timer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertFalse(activated)
        XCTAssertTrue(cancelled)
    }

    // MARK: - 13. Option release → deactivated

    func test_option_release_deactivates() {
        let mockEvents = MockEventMonitoring()
        let sut = OptionKeyMonitor(eventMonitor: mockEvents)

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        mockEvents.simulateOptionDown()

        let expectActivation = expectation(description: "wait for activation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectActivation.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockEvents.simulateOptionUp()
        XCTAssertTrue(deactivated)
    }

    // MARK: - 14. stopMonitoring удаляет все мониторы

    func test_stop_monitoring_removes_monitors() {
        let mockEvents = MockEventMonitoring()
        let sut = OptionKeyMonitor(eventMonitor: mockEvents)

        sut.startMonitoring()
        sut.stopMonitoring()

        // 4 монитора: global flags, global keyDown, local flags, local keyDown
        XCTAssertEqual(mockEvents.removeMonitorCallCount, 4)
    }
}
