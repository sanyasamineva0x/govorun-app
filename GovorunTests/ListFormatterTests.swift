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
}
