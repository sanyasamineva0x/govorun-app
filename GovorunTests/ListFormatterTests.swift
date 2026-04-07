@testable import Govorun
import XCTest

final class ListFormatterTests: XCTestCase {
    // MARK: - Порядковые маркеры (2+)

    func test_ordinal_two_items() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_ordinal_three_items() {
        let input = "первое молоко второе хлеб третье масло"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб\n3. Масло")
    }

    func test_ordinal_single_no_change() {
        let input = "первое впечатление хорошее"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "первое впечатление хорошее")
    }

    // MARK: - Наречия (2+)

    func test_adverb_two_items() {
        let input = "во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_adverb_single_no_change() {
        let input = "во-первых это неправда"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "во-первых это неправда")
    }

    // MARK: - Пункты (2+)

    func test_punkt_two_items() {
        let input = "пункт один задача пункт два баг"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Задача\n2. Баг")
    }

    // MARK: - Без маркеров

    func test_no_markers_unchanged() {
        let input = "просто обычный текст без маркеров"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "просто обычный текст без маркеров")
    }

    func test_empty_string() {
        XCTAssertEqual(ListFormatter.format(""), "")
    }

    // MARK: - Дефисные маркеры

    func test_dashed_phrase_two_items() {
        let input = "кроме того скорость а также простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота")
    }

    func test_dashed_single_word_three_items() {
        let input = "плюс скорость плюс простота плюс цена"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота\n– Цена")
    }

    func test_dashed_single_word_two_no_change() {
        let input = "плюс скорость плюс простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюс скорость плюс простота")
    }

    func test_dashed_single_no_change() {
        let input = "плюс этого подхода в скорости"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюс этого подхода в скорости")
    }

    // MARK: - Overlap suppression: «а также» vs «также»

    func test_a_takzhe_not_double_counted() {
        // «а также» — один фразовый маркер, «также» внутри не порождает отдельный матч
        let input = "а также скорость помимо этого простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота")
    }

    func test_takzhe_inside_a_takzhe_not_separate_match() {
        let input = "а также скорость"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "а также скорость", "одиночный маркер — без изменений")
    }

    // MARK: - Weak dashed false positives

    func test_takzhe_in_normal_speech_no_change() {
        let input = "я также думаю что также важно учитывать"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "я также думаю что также важно учитывать",
                       "2x «также» недостаточно — порог 3+")
    }

    func test_eshchyo_in_normal_speech_no_change() {
        let input = "ещё раз напомню что ещё нужно проверить"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "ещё раз напомню что ещё нужно проверить",
                       "2x «ещё» недостаточно — порог 3+")
    }

    // MARK: - Капитализация по стилю

    func test_relaxed_no_capitalization() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .relaxed)
        XCTAssertEqual(result, "1. молоко\n2. хлеб")
    }

    func test_normal_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .normal)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_formal_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .formal)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_nil_style_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: nil)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    // MARK: - Шапка

    func test_header_with_list() {
        let input = "нужно купить первое молоко второе хлеб третье масло"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "нужно купить\n1. Молоко\n2. Хлеб\n3. Масло")
    }

    func test_header_no_auto_colon() {
        let input = "плюсы этого подхода во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюсы этого подхода\n1. Скорость\n2. Простота")
    }

    func test_header_preserves_dictated_colon() {
        let input = "купить: первое молоко второе хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "купить:\n1. Молоко\n2. Хлеб")
    }

    func test_marker_at_start_no_header() {
        let input = "во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    // MARK: - Приоритет семей

    func test_numbered_beats_dashed() {
        let input = "ещё одна вещь во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "ещё одна вещь\n1. Скорость\n2. Простота")
    }

    func test_weak_family_does_not_block_strong() {
        let input = "плюс контекст во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюс контекст\n1. Скорость\n2. Простота")
    }

    // MARK: - Robustness

    func test_duplicate_marker_same_word() {
        let input = "первое молоко первое хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_out_of_order_markers() {
        let input = "второе хлеб первое молоко"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Хлеб\n2. Молоко")
    }

    func test_consecutive_markers_no_content_fallback() {
        let input = "во-первых во-вторых"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "во-первых во-вторых",
                       "нет непустых items — fallback на исходный текст")
    }

    func test_markers_with_one_empty_item() {
        let input = "во-первых во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "во-первых во-вторых простота",
                       "только 1 непустой item — fallback")
    }

    // MARK: - Очистка пунктуации

    func test_comma_after_marker_stripped() {
        let input = "во-первых, скорость, во-вторых, простота."
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_dash_after_marker_stripped() {
        let input = "первое — молоко второе — хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_period_stripped() {
        let input = "первое молоко. второе хлеб."
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_semicolon_stripped() {
        let input = "первое молоко; второе хлеб;"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_comma_stripped() {
        let input = "первое молоко, второе хлеб,"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_colon_stripped() {
        let input = "первое молоко: второе хлеб:"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_exclamation_stripped() {
        let input = "первое скорость! второе простота!"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_trailing_question_stripped() {
        let input = "первое скорость? второе простота?"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_mixed_punctuation_cleanup() {
        let input = "во-первых, скорость; во-вторых — простота. в-третьих, цена,"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота\n3. Цена")
    }

    // MARK: - Нормализованные формы (после NumberNormalizer)

    func test_normalized_ordinal_forms() {
        let input = "1-е молоко 2-е хлеб 3-е масло"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб\n3. Масло")
    }

    func test_normalized_punkt_forms() {
        let input = "пункт 1 задача пункт 2 баг"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Задача\n2. Баг")
    }

    // MARK: - Multi-word items

    func test_multi_word_items() {
        let input = "первое купить молоко второе позвонить маме"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Купить молоко\n2. Позвонить маме")
    }

    // MARK: - «помимо этого» маркер

    func test_pomimo_etogo_marker() {
        let input = "помимо этого скорость кроме того простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота")
    }

    // MARK: - Шапка + дефисный список

    func test_header_with_dashed_list() {
        let input = "преимущества кроме того скорость помимо этого простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "преимущества\n– Скорость\n– Простота")
    }

    // MARK: - Маркер после пунктуации

    func test_marker_after_punctuation() {
        let input = "список:первое молоко второе хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "список:\n1. Молоко\n2. Хлеб")
    }
}
