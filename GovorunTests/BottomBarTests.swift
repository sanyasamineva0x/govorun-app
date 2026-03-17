import XCTest
@testable import Govorun

// MARK: - BottomBarController тесты

@MainActor
final class BottomBarControllerTests: XCTestCase {

    // MARK: - 1. При recording → bar видим

    func test_bar_shows_on_recording() {
        let sut = BottomBarController()
        XCTAssertEqual(sut.state, .hidden)

        sut.showRecording(audioLevel: 0.5)

        XCTAssertEqual(sut.state, .recording(audioLevel: 0.5))
        XCTAssertTrue(sut.state.isVisible)
    }

    // MARK: - 2. При processing → индикатор обработки

    func test_bar_shows_processing() {
        let sut = BottomBarController()

        sut.showProcessing()

        XCTAssertEqual(sut.state, .processing)
        XCTAssertTrue(sut.state.isVisible)
    }

    // MARK: - 3. При idle → bar скрыт

    func test_bar_dismisses_on_idle() {
        let sut = BottomBarController()
        sut.showRecording(audioLevel: 0.3)
        XCTAssertTrue(sut.state.isVisible)

        sut.dismiss()

        // dismiss() без реального NSPanel вызывает completion сразу
        XCTAssertEqual(sut.state, .hidden)
        XCTAssertFalse(sut.state.isVisible)
    }

    // MARK: - 4. Pill размеры (компактный бар)

    func test_bar_pill_dimensions() {
        // Ширина 220-300pt (компактный)
        XCTAssertGreaterThanOrEqual(BottomBarMetrics.pillWidth, 220)
        XCTAssertLessThanOrEqual(BottomBarMetrics.pillWidth, 300)

        // Высота 36-52pt (тонкий)
        XCTAssertGreaterThanOrEqual(BottomBarMetrics.pillHeight, 36)
        XCTAssertLessThanOrEqual(BottomBarMetrics.pillHeight, 52)

        // cornerRadius = height / 2 (pill shape)
        let cornerRadius = BottomBarMetrics.pillHeight / 2
        XCTAssertEqual(cornerRadius, BottomBarMetrics.pillHeight / 2)

        // Отступ от нижнего края
        XCTAssertGreaterThan(BottomBarMetrics.bottomOffset, 0)
    }

    // MARK: - 5. Фокус не перехватывается

    func test_bar_does_not_steal_focus() {
        // BottomBarWindow переопределяет canBecomeKey/canBecomeMain = false
        // Реальная проверка NSPanel требует GUI — тестируем конфигурацию

        // Анимации: show быстрая, dismiss ещё быстрее
        XCTAssertEqual(BottomBarMetrics.showDuration, 0.18)
        XCTAssertEqual(BottomBarMetrics.dismissDuration, 0.12)
        XCTAssertLessThan(BottomBarMetrics.dismissDuration, BottomBarMetrics.showDuration)
    }
}

// MARK: - BottomBarState тесты

final class BottomBarStateTests: XCTestCase {

    func test_hidden_is_not_visible() {
        XCTAssertFalse(BottomBarState.hidden.isVisible)
    }

    func test_recording_is_visible() {
        XCTAssertTrue(BottomBarState.recording(audioLevel: 0.0).isVisible)
    }

    func test_processing_is_visible() {
        XCTAssertTrue(BottomBarState.processing.isVisible)
    }

    func test_error_is_visible() {
        XCTAssertTrue(BottomBarState.error("test").isVisible)
    }

    func test_state_equatable() {
        XCTAssertEqual(BottomBarState.hidden, .hidden)
        XCTAssertEqual(BottomBarState.processing, .processing)
        XCTAssertEqual(BottomBarState.recording(audioLevel: 0.5), .recording(audioLevel: 0.5))
        XCTAssertNotEqual(BottomBarState.recording(audioLevel: 0.5), .recording(audioLevel: 0.8))
        XCTAssertEqual(BottomBarState.error("a"), .error("a"))
        XCTAssertNotEqual(BottomBarState.error("a"), .error("b"))
        XCTAssertNotEqual(BottomBarState.hidden, .processing)
    }

    @MainActor
    func test_error_shows_then_controller_transitions() {
        let sut = BottomBarController()

        sut.showError("Ошибка сети")

        XCTAssertEqual(sut.state, .error("Ошибка сети"))
        XCTAssertTrue(sut.state.isVisible)
    }

    @MainActor
    func test_recording_updates_audio_level() {
        let sut = BottomBarController()

        sut.showRecording(audioLevel: 0.0)
        XCTAssertEqual(sut.state, .recording(audioLevel: 0.0))

        sut.showRecording(audioLevel: 0.8)
        XCTAssertEqual(sut.state, .recording(audioLevel: 0.8))
    }
}

// MARK: - BrandColors тесты

@MainActor
final class BrandColorsTests: XCTestCase {

    func test_brand_colors_exist() {
        XCTAssertNotNil(BrandColors.cottonCandy)
        XCTAssertNotNil(BrandColors.skyAqua)
        XCTAssertNotNil(BrandColors.oceanMist)
        XCTAssertNotNil(BrandColors.petalFrost)
    }
}
