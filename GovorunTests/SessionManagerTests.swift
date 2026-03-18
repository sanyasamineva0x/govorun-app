import XCTest
@testable import Govorun

// MARK: - Мок EventMonitoring

final class MockEventMonitoring: EventMonitoring, @unchecked Sendable {
    var activationKey: ActivationKey = .default
    private var flagsHandlers: [(CGEventFlags) -> Void] = []
    private var keyDownHandlers: [(UInt16) -> Void] = []
    private var keyUpHandlers: [(UInt16) -> Void] = []
    private(set) var removeMonitorCallCount = 0
    private var nextMonitorId = 0

    func addGlobalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any? {
        flagsHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addGlobalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any? {
        keyDownHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addGlobalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any? {
        keyUpHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addLocalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any? {
        flagsHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addLocalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any? {
        keyDownHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func addLocalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any? {
        keyUpHandlers.append(handler)
        nextMonitorId += 1
        return nextMonitorId
    }

    func removeMonitor(_ monitor: Any) {
        removeMonitorCallCount += 1
    }

    // Симуляция событий
    func simulateOptionDown() {
        flagsHandlers.forEach { $0(.maskAlternate) }
    }

    func simulateOptionUp() {
        flagsHandlers.forEach { $0(CGEventFlags()) }
    }

    func simulateFlagsChanged(_ flags: CGEventFlags) {
        flagsHandlers.forEach { $0(flags) }
    }

    func simulateKeyDown(keyCode: UInt16 = 0) {
        keyDownHandlers.forEach { $0(keyCode) }
    }

    func simulateKeyUp(keyCode: UInt16 = 0) {
        keyUpHandlers.forEach { $0(keyCode) }
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
