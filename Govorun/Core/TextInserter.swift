import Foundation

// MARK: - Протокол вставки текста

protocol TextInserting: Sendable {
    func insert(_ text: String) async throws
}

// MARK: - Метод вставки (для логирования)

enum InsertionMethod: String {
    case selectedText
    case composition
    case clipboard

    var asInsertionStrategy: InsertionStrategy {
        switch self {
        case .selectedText: .axSelectedText
        case .composition: .axValueComposition
        case .clipboard: .clipboard
        }
    }
}

// MARK: - Ошибки

enum TextInsertionError: Error, Equatable {
    case allStrategiesFailed
}

// MARK: - Протоколы для тестируемости

/// Абстракция над AXUIElement
protocol AXFocusedElementProtocol {
    func isSettable(_ attribute: String) -> Bool
    func getAttribute(_ attribute: String) -> Any?
    func setAttribute(_ attribute: String, value: Any) throws
}

/// Абстракция над Accessibility API
protocol AccessibilityProviding {
    func isTrusted() -> Bool
    func getFocusedElement() -> AXFocusedElementProtocol?
}

/// Элемент буфера обмена (для save/restore)
struct ClipboardItem: Equatable {
    let type: String
    let data: Data
    let itemIndex: Int
}

/// Абстракция над NSPasteboard
protocol ClipboardProviding {
    func save() -> [ClipboardItem]
    func restore(_ items: [ClipboardItem])
    func setString(_ text: String)
    func simulatePaste() async
}

// MARK: - Вставка с waterfall стратегиями

final class TextInserterEngine: TextInserting, @unchecked Sendable {
    private let accessibility: AccessibilityProviding
    private let clipboard: ClipboardProviding
    private let lock = NSLock()

    /// Последний использованный метод (для логирования)
    private var _lastInsertionMethod: InsertionMethod?
    var lastInsertionMethod: InsertionMethod? {
        lock.withLock { _lastInsertionMethod }
    }

    init(accessibility: AccessibilityProviding, clipboard: ClipboardProviding) {
        self.accessibility = accessibility
        self.clipboard = clipboard
    }

    func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }

        // Стратегия 1: selectedText replacement
        if let element = accessibility.getFocusedElement(),
           element.isSettable("AXSelectedText")
        {
            do {
                try element.setAttribute("AXSelectedText", value: text)
                lock.withLock { _lastInsertionMethod = .selectedText }
                return
            } catch {
                // Fallthrough
            }
        }

        // Стратегия 2: value composition
        if let element = accessibility.getFocusedElement(),
           element.isSettable("AXValue"),
           let currentValue = element.getAttribute("AXValue") as? String,
           let range = element.getAttribute("AXSelectedTextRange") as? [String: Int],
           let location = range["location"],
           let length = range["length"]
        {
            let newValue = compose(currentValue, inserting: text, at: location, length: length)
            do {
                try element.setAttribute("AXValue", value: newValue)
                let newCaret: [String: Int] = ["location": location + text.utf16.count, "length": 0]
                try? element.setAttribute("AXSelectedTextRange", value: newCaret)
                lock.withLock { _lastInsertionMethod = .composition }
                return
            } catch {
                // Fallthrough
            }
        }

        // Стратегия 3: clipboard sandwich
        try await insertViaClipboard(text)
    }

    // MARK: - Private

    func compose(_ current: String, inserting text: String, at location: Int, length: Int) -> String {
        guard location >= 0, length >= 0 else {
            return current + text
        }
        let utf16 = current.utf16
        let safeLocation = min(location, utf16.count)
        let safeEnd = min(safeLocation + length, utf16.count)

        let start = utf16.index(utf16.startIndex, offsetBy: safeLocation)
        let end = utf16.index(utf16.startIndex, offsetBy: safeEnd)
        return String(current[..<start]) + text + String(current[end...])
    }

    private func insertViaClipboard(_ text: String) async throws {
        let saved = clipboard.save()
        clipboard.setString(text)
        await clipboard.simulatePaste()
        clipboard.restore(saved)
        lock.withLock { _lastInsertionMethod = .clipboard }
    }
}
