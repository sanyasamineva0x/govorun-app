import CoreGraphics
@testable import Govorun
import XCTest

// MARK: - ActivationKeyMonitor тесты

@MainActor
final class ActivationKeyMonitorTests: XCTestCase {
    // MARK: - Вспомогательные методы

    /// Ожидание на главной очереди с небольшим запасом
    private func waitMain(_ seconds: TimeInterval, description: String = "ожидание") {
        let exp = expectation(description: description)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        waitForExpectations(timeout: seconds + 1)
    }

    // MARK: - Modifier: 1. Удержание 200мс активирует

    func test_modifier_hold_200ms_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)

        waitMain(0.3, description: "активация после 200мс")

        XCTAssertTrue(activated)
    }

    // MARK: - Modifier: 2. Быстрый тап не активирует

    func test_modifier_quick_tap_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateFlagsChanged(CGEventFlags()) // быстро отпускаем

        waitMain(0.3, description: "ожидание таймера")

        XCTAssertFalse(activated)
    }

    // MARK: - Modifier: 3. Modifier + другая клавиша → cancelled

    func test_modifier_plus_key_cancels() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        var activated = false
        var cancelled = false
        sut.onActivated = { activated = true }
        sut.onCancelled = { cancelled = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateKeyDown(keyCode: 8) // ⌥+C — шорткат

        waitMain(0.3, description: "ожидание")

        XCTAssertFalse(activated)
        XCTAssertTrue(cancelled)
    }

    // MARK: - Modifier: 4. Отпускание после активации → deactivated

    func test_modifier_release_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3, description: "ожидание активации")

        mock.simulateFlagsChanged(CGEventFlags()) // отпускаем
        XCTAssertTrue(deactivated)
    }

    // MARK: - Modifier: 5. stopMonitoring удаляет все 6 мониторов

    func test_modifier_stop_removes_all_monitors() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        sut.startMonitoring()
        sut.stopMonitoring()

        XCTAssertEqual(mock.removeMonitorCallCount, 6)
    }

    // MARK: - Modifier: 6. Command hold активирует

    func test_modifier_command_hold_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskCommand),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand)
        waitMain(0.3, description: "активация ⌘")

        XCTAssertTrue(activated)
    }

    // MARK: - Modifier: 7. Чужой модификатор игнорируется

    func test_modifier_wrong_modifier_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand) // не тот модификатор

        waitMain(0.3, description: "ожидание")

        XCTAssertFalse(activated)
    }

    // MARK: - KeyCode: 8. Удержание клавиши активирует

    func test_keyCode_hold_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96), // F5
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3, description: "активация F5")

        XCTAssertTrue(activated)
    }

    // MARK: - KeyCode: 9. Быстрый тап не активирует

    func test_keyCode_quick_tap_not_activated() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        mock.simulateKeyUp(keyCode: 96)

        waitMain(0.3, description: "ожидание таймера")

        XCTAssertFalse(activated)
    }

    // MARK: - KeyCode: 10. Отпускание после активации → deactivated

    func test_keyCode_release_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            eventMonitor: mock
        )

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3, description: "активация")

        mock.simulateKeyUp(keyCode: 96)
        XCTAssertTrue(deactivated)
    }

    // MARK: - KeyCode: 11. Другая клавиша игнорируется

    func test_keyCode_wrong_key_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 97) // не та клавиша

        waitMain(0.3, description: "ожидание")

        XCTAssertFalse(activated)
    }

    // MARK: - KeyCode: 12. Авторепит не вызывает повторную активацию

    func test_keyCode_autorepeat_suppressed() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            eventMonitor: mock
        )

        var activatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3, description: "первая активация")

        // Авторепит — клавиша всё ещё зажата
        mock.simulateKeyDown(keyCode: 96)
        mock.simulateKeyDown(keyCode: 96)
        mock.simulateKeyDown(keyCode: 96)

        XCTAssertEqual(activatedCount, 1)
    }

    // MARK: - Combo: 13. Modifier + key активирует

    func test_combo_modifier_plus_key_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40), // ⌘K
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)

        waitMain(0.3, description: "активация ⌘K")

        XCTAssertTrue(activated)
    }

    // MARK: - Combo: 14. Отпустить modifier до таймера → не активирует

    func test_combo_modifier_released_before_key_not_activated() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateFlagsChanged(CGEventFlags()) // отпустили ⌘

        waitMain(0.3, description: "ожидание")

        XCTAssertFalse(activated)
    }

    // MARK: - Combo: 15. Клавиша без модификатора не активирует

    func test_combo_key_without_modifier_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        // Жмём K без ⌘
        mock.simulateKeyDown(keyCode: 40)

        waitMain(0.3, description: "ожидание")

        XCTAssertFalse(activated)
    }

    // MARK: - Combo: 16. Отпускание клавиши после активации → deactivated

    func test_combo_release_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            eventMonitor: mock
        )

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3, description: "активация")

        mock.simulateKeyUp(keyCode: 40)
        XCTAssertTrue(deactivated)
    }

    // MARK: - Toggle Modifier: 17. Tap (hold 200ms + release) активирует

    func test_toggle_modifier_tap_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3, description: "armed после 200мс")
        XCTAssertFalse(activated, "Toggle не активирует при удержании")

        mock.simulateFlagsChanged(CGEventFlags()) // отпускаем → активация
        XCTAssertTrue(activated)
    }

    // MARK: - Toggle Modifier: 18. Повторный tap деактивирует

    func test_toggle_modifier_second_tap_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        var deactivated = false
        sut.onActivated = { activated = true }
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        // Первый tap → активация
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertTrue(activated)

        // Второй tap → деактивация
        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertTrue(deactivated)
    }

    // MARK: - Toggle Modifier: 19. Быстрый тап (<200мс) не активирует

    func test_toggle_modifier_quick_tap_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateFlagsChanged(CGEventFlags()) // быстро отпускаем

        waitMain(0.3)

        XCTAssertFalse(activated)
    }

    // MARK: - Toggle KeyCode: 20. Tap активирует

    func test_toggle_keyCode_tap_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3)
        XCTAssertFalse(activated)

        mock.simulateKeyUp(keyCode: 96)
        XCTAssertTrue(activated)
    }

    // MARK: - Toggle KeyCode: 21. Повторный tap деактивирует

    func test_toggle_keyCode_second_tap_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        // Первый tap
        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 96)

        // Второй tap
        mock.simulateKeyDown(keyCode: 96)
        mock.simulateKeyUp(keyCode: 96)
        XCTAssertTrue(deactivated)
    }

    // MARK: - Toggle KeyCode: 22. Быстрый тап не активирует

    func test_toggle_keyCode_quick_tap_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateKeyDown(keyCode: 96)
        mock.simulateKeyUp(keyCode: 96)

        waitMain(0.3)
        XCTAssertFalse(activated)
    }

    // MARK: - Toggle Combo: 23. Tap активирует

    func test_toggle_combo_tap_activates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        XCTAssertFalse(activated)

        mock.simulateKeyUp(keyCode: 40)
        XCTAssertTrue(activated)
    }

    // MARK: - Toggle Combo: 24. Повторный tap деактивирует

    func test_toggle_combo_second_tap_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var deactivated = false
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        // Первый tap
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 40)

        // Второй tap (модификатор всё ещё зажат)
        mock.simulateKeyDown(keyCode: 40)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertTrue(deactivated)
    }

    // MARK: - Toggle Modifier: 25. Modifier + другая клавиша при armed → cancelled

    func test_toggle_modifier_plus_key_while_armed_cancels() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        var cancelled = false
        sut.onActivated = { activated = true }
        sut.onCancelled = { cancelled = true }
        sut.startMonitoring()

        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3) // armed
        mock.simulateKeyDown(keyCode: 8) // ⌥+C шорткат

        XCTAssertFalse(activated)
        XCTAssertTrue(cancelled)
    }

    // MARK: - Toggle: 26. Rapid cycle (activate → deactivate → re-activate)

    func test_toggle_modifier_rapid_cycle_reactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.startMonitoring()

        // Первый цикл: tap on
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags(rawValue: 0)) // release → activate
        XCTAssertEqual(activatedCount, 1)

        // Первый цикл: tap off
        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateFlagsChanged(CGEventFlags(rawValue: 0)) // release → deactivate
        XCTAssertEqual(deactivatedCount, 1)

        // Второй цикл: tap on
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags(rawValue: 0)) // release → re-activate
        XCTAssertEqual(activatedCount, 2)
    }

    // MARK: - Toggle: 27. stopMonitoring while armed

    func test_toggle_stopMonitoring_while_armed_resets() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        // Arm (press + wait 200ms)
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)

        // Stop while armed — не должен активироваться при restart
        sut.stopMonitoring()
        sut.startMonitoring()

        // Release — не должен активировать (state сброшен)
        mock.simulateFlagsChanged(CGEventFlags(rawValue: 0))
        XCTAssertFalse(activated)
    }

    // MARK: - Toggle: 28. Modifier shortcut during active toggle recording

    func test_toggle_modifier_shortcut_during_recording_ignored() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        var cancelled = false
        var deactivated = false
        sut.onActivated = { activated = true }
        sut.onCancelled = { cancelled = true }
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        // Activate toggle recording
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags(rawValue: 0)) // release → activate
        XCTAssertTrue(activated)

        // Press ⌥+C while recording — should NOT cancel
        mock.simulateKeyDown(keyCode: 8)
        XCTAssertFalse(cancelled)
        XCTAssertFalse(deactivated)
    }
}
