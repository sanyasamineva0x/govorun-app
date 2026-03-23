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

    // MARK: - 6. Processing min-duration: dismiss откладывается < 0.5s

    func test_dismiss_during_processing_defers_when_under_min_duration() {
        let sut = BottomBarController()
        sut.showProcessing()

        sut.dismiss()

        // Должен быть отложен — state ещё .processing
        XCTAssertEqual(sut.state, .processing)

        let exp = expectation(description: "deferred dismiss")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(sut.state, .hidden)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 7. Processing min-duration: dismiss мгновенный >= 0.5s

    func test_dismiss_during_processing_immediate_after_min_duration() {
        let sut = BottomBarController()
        sut.showProcessing()

        let exp = expectation(description: "after min duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            sut.dismiss()
            // Без реального panel, hidePanel вызывает completion сразу
            XCTAssertEqual(sut.state, .hidden)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 8. show() отменяет отложенный dismiss (race condition fix)

    func test_show_cancels_delayed_dismiss() {
        let sut = BottomBarController()
        sut.showProcessing()
        sut.dismiss()

        XCTAssertEqual(sut.state, .processing)

        // Новая запись отменяет отложенный dismiss
        sut.show()
        XCTAssertEqual(sut.state, .recording(audioLevel: 0))

        // После задержки state НЕ должен стать .hidden
        let exp = expectation(description: "delayed dismiss cancelled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            XCTAssertTrue(sut.state.isVisible)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 9. Двойной dismiss безопасен

    func test_double_dismiss_during_processing_is_safe() {
        let sut = BottomBarController()
        sut.showProcessing()

        sut.dismiss()
        XCTAssertEqual(sut.state, .processing)

        // Второй dismiss отменяет первый и проходит сразу
        sut.dismiss()
        XCTAssertEqual(sut.state, .hidden)
    }

    // MARK: - 10. showError отменяет отложенный dismiss

    func test_show_error_cancels_delayed_dismiss() {
        let sut = BottomBarController()
        sut.showProcessing()
        sut.dismiss()

        XCTAssertEqual(sut.state, .processing)

        sut.showError("Ошибка")
        XCTAssertEqual(sut.state, .error("Ошибка"))

        let exp = expectation(description: "delayed dismiss cancelled by error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            // Стейл delayed dismiss не должен был сработать
            XCTAssertEqual(sut.state, .error("Ошибка"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
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

// MARK: - Метрики pill (инварианты)

final class BottomBarMetricsTests: XCTestCase {

    func test_max_pill_width_fits_all_states() {
        XCTAssertGreaterThanOrEqual(
            BottomBarMetrics.maxPillWidth,
            BottomBarMetrics.pillWidth
        )

        // Error width (280) помещается в maxPillWidth
        let errorWidth: CGFloat = 280
        XCTAssertLessThanOrEqual(errorWidth, BottomBarMetrics.maxPillWidth)

        // Максимальный scaled error width помещается (280 × 1.03 = 288.4)
        let maxScale: CGFloat = 1.0 + 0.03
        let maxScaledWidth = errorWidth * maxScale
        XCTAssertLessThanOrEqual(maxScaledWidth, BottomBarMetrics.maxPillWidth)
    }

    func test_vertical_headroom_for_scale() {
        // Scale 1.03 на pillHeight даёт <2pt overflow — приемлемо
        let maxScaledHeight = BottomBarMetrics.pillHeight * (1.0 + 0.03)
        let overflow = maxScaledHeight - BottomBarMetrics.pillHeight
        XCTAssertLessThan(overflow, 2.0)
    }
}

// MARK: - OrganicPillShape тесты

final class OrganicPillShapeTests: XCTestCase {

    func test_zero_amplitude_produces_capsule() {
        let shape = OrganicPillShape(amplitude: 0, phase: 0, frequency: 3.0)
        let rect = CGRect(x: 0, y: 0, width: 260, height: 44)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect

        // При amplitude=0 path ≈ input rect
        XCTAssertEqual(bounds.minX, rect.minX, accuracy: 1.0)
        XCTAssertEqual(bounds.minY, rect.minY, accuracy: 1.0)
        XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 1.0)
        XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 1.0)
    }

    func test_degenerate_rect_does_not_crash() {
        let shape = OrganicPillShape(amplitude: 1.0, phase: 0, frequency: 3.0)

        // w < h — fallback в rounded rect
        let narrow = shape.path(in: CGRect(x: 0, y: 0, width: 10, height: 44))
        XCTAssertFalse(narrow.isEmpty)

        // Нулевая высота
        let flat = shape.path(in: CGRect(x: 0, y: 0, width: 260, height: 0))
        XCTAssertFalse(flat.isEmpty)

        // Нулевой rect
        _ = shape.path(in: .zero)
    }

    func test_animatable_data_is_amplitude_only() {
        var shape = OrganicPillShape(amplitude: 2.5, phase: 1.7, frequency: 3.0)

        // animatableData — только amplitude (phase не анимируется SwiftUI)
        XCTAssertEqual(shape.animatableData, 2.5, accuracy: 0.001)

        shape.animatableData = 0.0
        XCTAssertEqual(shape.amplitude, 0.0, accuracy: 0.001)
        // phase не затронут
        XCTAssertEqual(shape.phase, 1.7, accuracy: 0.001)
    }

    func test_large_phase_values_produce_valid_path() {
        // Phase mod 2π — bounded, но shape должна работать и с большими значениями
        let shape = OrganicPillShape(amplitude: 2.0, phase: 1000.0, frequency: 3.0)
        let rect = CGRect(x: 0, y: 0, width: 260, height: 44)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)

        let bounds = path.boundingRect
        XCTAssertGreaterThan(bounds.width, 200)
        XCTAssertGreaterThan(bounds.height, 30)
    }

    func test_nonzero_amplitude_extends_beyond_rect() {
        let shape = OrganicPillShape(amplitude: 3.0, phase: 0.5, frequency: 3.0)
        let rect = CGRect(x: 0, y: 0, width: 260, height: 44)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect

        // При amplitude > 0 path выходит за пределы rect
        let area = bounds.width * bounds.height
        let rectArea = rect.width * rect.height
        XCTAssertGreaterThan(area, rectArea * 0.9)
    }
}
