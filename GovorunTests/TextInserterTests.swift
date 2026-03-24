@testable import Govorun
import XCTest

// MARK: - Мок AXFocusedElement

final class MockAXElement: AXFocusedElementProtocol {
    var settableAttributes: Set<String> = []
    var attributes: [String: Any] = [:]
    var setAttributeError: Error?
    private(set) var setAttributeCalls: [(attribute: String, value: Any)] = []

    func isSettable(_ attribute: String) -> Bool {
        settableAttributes.contains(attribute)
    }

    func getAttribute(_ attribute: String) -> Any? {
        attributes[attribute]
    }

    func setAttribute(_ attribute: String, value: Any) throws {
        if let error = setAttributeError { throw error }
        setAttributeCalls.append((attribute, value))
        attributes[attribute] = value
    }
}

// MARK: - Мок AccessibilityProviding

final class MockAccessibility: AccessibilityProviding {
    var trusted = true
    var focusedElement: AXFocusedElementProtocol?

    func isTrusted() -> Bool {
        trusted
    }

    func getFocusedElement() -> AXFocusedElementProtocol? {
        focusedElement
    }
}

// MARK: - Мок ClipboardProviding

final class MockClipboard: ClipboardProviding {
    var savedItems: [ClipboardItem] = []
    private(set) var saveCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var restoredItems: [ClipboardItem]?
    private(set) var setStringValue: String?
    private(set) var simulatePasteCallCount = 0

    func save() -> [ClipboardItem] {
        saveCallCount += 1
        return savedItems
    }

    func restore(_ items: [ClipboardItem]) {
        restoreCallCount += 1
        restoredItems = items
    }

    func setString(_ text: String) {
        setStringValue = text
    }

    func simulatePaste() async {
        simulatePasteCallCount += 1
    }
}

// MARK: - TextInserterEngine тесты

final class TextInserterTests: XCTestCase {
    // MARK: - 1. Пустая строка → ничего не делаем

    func test_insert_empty_string_noop() async throws {
        let accessibility = MockAccessibility()
        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("")

        XCTAssertNil(sut.lastInsertionMethod)
        XCTAssertEqual(clipboard.saveCallCount, 0)
    }

    // MARK: - 2. Стратегия 1: selectedText вставка в caret

    func test_selected_text_insert_at_caret() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXSelectedText"]
        element.attributes = ["AXValue": "Привет мир"]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("красивый ")

        XCTAssertEqual(sut.lastInsertionMethod, .selectedText)
        XCTAssertEqual(element.setAttributeCalls.count, 1)
        XCTAssertEqual(element.setAttributeCalls[0].attribute, "AXSelectedText")
        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "красивый ")
        // Clipboard не трогали
        XCTAssertEqual(clipboard.saveCallCount, 0)
    }

    // MARK: - 3. Стратегия 1: замена выделения

    func test_selected_text_replaces_selection() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXSelectedText"]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("новый текст")

        XCTAssertEqual(sut.lastInsertionMethod, .selectedText)
        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "новый текст")
    }

    // MARK: - 4. Стратегия 1: пустое поле

    func test_selected_text_empty_field() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXSelectedText"]
        element.attributes = ["AXValue": ""]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("Привет")

        XCTAssertEqual(sut.lastInsertionMethod, .selectedText)
        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "Привет")
    }

    // MARK: - 5. Стратегия 2: composition fallback

    func test_composition_fallback() async throws {
        let element = MockAXElement()
        // selectedText НЕ settable, но value — settable
        element.settableAttributes = ["AXValue"]
        element.attributes = [
            "AXValue": "Привет мир",
            "AXSelectedTextRange": ["location": 7, "length": 0],
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("красивый ")

        XCTAssertEqual(sut.lastInsertionMethod, .composition)
        // "Привет " + "красивый " + "мир" = "Привет красивый мир"
        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "Привет красивый мир")
    }

    // MARK: - 6. Composition: текст вокруг caret сохраняется

    func test_composition_preserves_surrounding() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXValue"]
        element.attributes = [
            "AXValue": "ABCDEF",
            "AXSelectedTextRange": ["location": 3, "length": 0],
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("XYZ")

        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "ABCXYZDEF")
    }

    // MARK: - 7. Composition: курсор перемещается после вставки

    func test_composition_moves_caret() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXValue"]
        element.attributes = [
            "AXValue": "Hello world",
            "AXSelectedTextRange": ["location": 5, "length": 0],
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert(" beautiful")

        // Проверяем что курсор установлен после вставленного текста
        XCTAssertEqual(element.setAttributeCalls.count, 2)
        let caretCall = element.setAttributeCalls[1]
        XCTAssertEqual(caretCall.attribute, "AXSelectedTextRange")
        let range = caretCall.value as? [String: Int]
        XCTAssertEqual(range?["location"], 15) // 5 + " beautiful".count
        XCTAssertEqual(range?["length"], 0)
    }

    // MARK: - 8. Стратегия 3: clipboard fallback

    func test_clipboard_fallback() async throws {
        // AX недоступен — нет focused element
        let accessibility = MockAccessibility()
        accessibility.focusedElement = nil

        let clipboard = MockClipboard()
        clipboard.savedItems = try [ClipboardItem(type: "public.utf8-plain-text", data: XCTUnwrap("старое".data(using: .utf8)), itemIndex: 0)]

        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("новый текст")

        XCTAssertEqual(sut.lastInsertionMethod, .clipboard)
        XCTAssertEqual(clipboard.saveCallCount, 1)
        XCTAssertEqual(clipboard.setStringValue, "новый текст")
        XCTAssertEqual(clipboard.simulatePasteCallCount, 1)
    }

    // MARK: - 9. Clipboard: буфер восстанавливается

    func test_clipboard_restored_after_insert() async throws {
        let accessibility = MockAccessibility()
        accessibility.focusedElement = nil

        let savedItems = try [
            ClipboardItem(type: "public.utf8-plain-text", data: XCTUnwrap("важные данные".data(using: .utf8)), itemIndex: 0),
            ClipboardItem(type: "public.rtf", data: XCTUnwrap("rtf data".data(using: .utf8)), itemIndex: 0),
        ]
        let clipboard = MockClipboard()
        clipboard.savedItems = savedItems

        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("текст")

        XCTAssertEqual(clipboard.restoreCallCount, 1)
        XCTAssertEqual(clipboard.restoredItems, savedItems)
    }

    // MARK: - 10. Clipboard: rich content восстанавливается

    func test_clipboard_save_restore_rich_content() async throws {
        let accessibility = MockAccessibility()
        accessibility.focusedElement = nil

        let imageData = Data([0x89, 0x50, 0x4e, 0x47]) // PNG header
        let richItems = try [
            ClipboardItem(type: "public.png", data: imageData, itemIndex: 0),
            ClipboardItem(type: "public.utf8-plain-text", data: XCTUnwrap("caption".data(using: .utf8)), itemIndex: 0),
            ClipboardItem(type: "public.html", data: XCTUnwrap("<b>bold</b>".data(using: .utf8)), itemIndex: 0),
        ]
        let clipboard = MockClipboard()
        clipboard.savedItems = richItems

        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("вставка")

        XCTAssertEqual(clipboard.restoredItems, richItems)
    }

    // MARK: - 10b. Clipboard: группировка multi-item сохраняется

    func test_clipboard_restore_groups_by_itemIndex() {
        // Тестируем реальный SystemClipboardProvider через NSPasteboard
        let provider = SystemClipboardProvider()
        let pasteboard = NSPasteboard.general

        // Подготовить pasteboard с двумя items
        pasteboard.clearContents()
        let pbItem0 = NSPasteboardItem()
        pbItem0.setString("hello", forType: .string)
        let pbItem1 = NSPasteboardItem()
        pbItem1.setString("world", forType: .string)
        pasteboard.writeObjects([pbItem0, pbItem1])

        // save → должно быть 2 группы (itemIndex 0 и 1)
        let saved = provider.save()
        let groups = Set(saved.map(\.itemIndex))
        XCTAssertEqual(groups.count, 2, "save() должен сохранить 2 группы")

        // Перезаписать pasteboard чем-то другим
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)

        // restore → должно вернуть 2 items
        provider.restore(saved)

        // Проверить что pasteboard содержит 2 items
        let restoredCount = pasteboard.pasteboardItems?.count ?? 0
        XCTAssertEqual(restoredCount, 2, "restore() должен восстановить 2 pasteboard items")
    }

    func test_clipboard_multi_item_round_trip() async throws {
        let accessibility = MockAccessibility()
        accessibility.focusedElement = nil

        let multiItems = try [
            ClipboardItem(type: "public.utf8-plain-text", data: XCTUnwrap("a".data(using: .utf8)), itemIndex: 0),
            ClipboardItem(type: "public.utf8-plain-text", data: XCTUnwrap("b".data(using: .utf8)), itemIndex: 1),
        ]
        let clipboard = MockClipboard()
        clipboard.savedItems = multiItems

        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)
        try await sut.insert("текст")

        XCTAssertEqual(clipboard.restoredItems?.count, 2)
        XCTAssertEqual(Set(clipboard.restoredItems?.map(\.itemIndex) ?? []).count, 2)
    }

    // MARK: - 11. Waterfall: стратегии пробуются в порядке 1→2→3

    func test_waterfall_order() async throws {
        // selectedText settable → используем стратегию 1, не 2 или 3
        let element = MockAXElement()
        element.settableAttributes = ["AXSelectedText", "AXValue"]
        element.attributes = [
            "AXValue": "текст",
            "AXSelectedTextRange": ["location": 0, "length": 0],
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("новый")

        XCTAssertEqual(sut.lastInsertionMethod, .selectedText)
        XCTAssertEqual(clipboard.saveCallCount, 0) // clipboard не использовался
    }

    // MARK: - 12. Стратегия 1 падает → fallback к стратегии 2

    func test_strategy1_fails_falls_to_strategy2() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXSelectedText", "AXValue"]
        element.setAttributeError = TextInsertionError.allStrategiesFailed
        element.attributes = [
            "AXValue": "Hello",
            "AXSelectedTextRange": ["location": 5, "length": 0],
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        // setAttribute кидает ошибку на первом вызове (стратегия 1),
        // и на втором (стратегия 2) — тоже. Тогда fallback к clipboard.
        try await sut.insert("World")

        XCTAssertEqual(sut.lastInsertionMethod, .clipboard)
    }

    // MARK: - 13. Composition: замена выделенного фрагмента

    func test_composition_replaces_selection() async throws {
        let element = MockAXElement()
        element.settableAttributes = ["AXValue"]
        element.attributes = [
            "AXValue": "Hello World",
            "AXSelectedTextRange": ["location": 6, "length": 5], // "World" выделен
        ]

        let accessibility = MockAccessibility()
        accessibility.focusedElement = element

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        try await sut.insert("Swift")

        XCTAssertEqual(sut.lastInsertionMethod, .composition)
        XCTAssertEqual(element.setAttributeCalls[0].value as? String, "Hello Swift")
    }

    // MARK: - 14. Thread safety: lastInsertionMethod

    // Полная проверка — xcodebuild test -enableThreadSanitizer YES

    func test_lastInsertionMethod_threadSafe() {
        let accessibility = MockAccessibility()
        accessibility.focusedElement = nil

        let clipboard = MockClipboard()
        let sut = TextInserterEngine(accessibility: accessibility, clipboard: clipboard)

        // Pre-allocate expectations на main thread (expectation() не thread-safe)
        let expectations = (0..<50).map { expectation(description: "insert-\($0)") }

        DispatchQueue.concurrentPerform(iterations: 100) { i in
            if i % 2 == 0 {
                let exp = expectations[i/2]
                Task {
                    try? await sut.insert("test")
                    exp.fulfill()
                }
            } else {
                _ = sut.lastInsertionMethod
            }
        }
        waitForExpectations(timeout: 10)
    }
}

// MARK: - compose() тесты

final class ComposeTests: XCTestCase {
    func test_compose_insert_at_beginning() {
        let sut = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )
        let result = sut.compose("World", inserting: "Hello ", at: 0, length: 0)
        XCTAssertEqual(result, "Hello World")
    }

    func test_compose_insert_at_end() {
        let sut = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )
        let result = sut.compose("Hello", inserting: " World", at: 5, length: 0)
        XCTAssertEqual(result, "Hello World")
    }

    func test_compose_replace_range() {
        let sut = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )
        let result = sut.compose("Hello World", inserting: "Swift", at: 6, length: 5)
        XCTAssertEqual(result, "Hello Swift")
    }

    func test_compose_unicode() {
        let sut = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )
        let result = sut.compose("Привет мир", inserting: "красивый ", at: 7, length: 0)
        XCTAssertEqual(result, "Привет красивый мир")
    }

    func test_compose_out_of_bounds_clamped() {
        let sut = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )
        let result = sut.compose("ABC", inserting: "XYZ", at: 100, length: 0)
        XCTAssertEqual(result, "ABCXYZ")
    }
}
