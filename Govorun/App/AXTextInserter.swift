import Cocoa
import ApplicationServices

// MARK: - AXUIElement обёртка

final class AXFocusedElement: AXFocusedElementProtocol {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    func getAttribute(_ attribute: String) -> Any? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        // AXSelectedTextRange → словарь с location/length
        if attribute == "AXSelectedTextRange", let axValue = value {
            // CF-тип: as? всегда успешен, unsafeBitCast — стандарт для CF interop
            let val = unsafeBitCast(axValue, to: AXValue.self)
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(val, .cfRange, &range) {
                return ["location": range.location, "length": range.length]
            }
            return nil
        }

        return value
    }

    func setAttribute(_ attribute: String, value: Any) throws {
        let cfValue: AnyObject

        if attribute == "AXSelectedTextRange",
           let range = value as? [String: Int],
           let location = range["location"],
           let length = range["length"] {
            var cfRange = CFRange(location: location, length: length)
            guard let axValue = AXValueCreate(.cfRange, &cfRange) else {
                throw TextInsertionError.allStrategiesFailed
            }
            cfValue = axValue
        } else if let str = value as? String {
            cfValue = str as NSString
        } else {
            throw TextInsertionError.allStrategiesFailed
        }

        let result = AXUIElementSetAttributeValue(element, attribute as CFString, cfValue)
        guard result == .success else {
            throw TextInsertionError.allStrategiesFailed
        }
    }
}

// MARK: - Accessibility провайдер

final class SystemAccessibilityProvider: AccessibilityProviding {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func getFocusedElement() -> AXFocusedElementProtocol? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return nil
        }

        guard let rawApp = focusedApp else { return nil }
        let app = unsafeBitCast(rawApp, to: AXUIElement.self)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        guard let rawElement = focusedElement else { return nil }
        let element = unsafeBitCast(rawElement, to: AXUIElement.self)
        return AXFocusedElement(element)
    }
}

// MARK: - Clipboard провайдер

final class SystemClipboardProvider: ClipboardProviding {
    private let pasteDelay: TimeInterval

    init(pasteDelay: TimeInterval = 0.3) {
        self.pasteDelay = pasteDelay
    }

    func save() -> [ClipboardItem] {
        let pasteboard = NSPasteboard.general
        var items: [ClipboardItem] = []

        guard let pasteboardItems = pasteboard.pasteboardItems else { return items }

        for (index, pbItem) in pasteboardItems.enumerated() {
            for type in pbItem.types {
                if let data = pbItem.data(forType: type) {
                    items.append(ClipboardItem(type: type.rawValue, data: data, itemIndex: index))
                }
            }
        }

        return items
    }

    func restore(_ items: [ClipboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !items.isEmpty else { return }

        let grouped = Dictionary(grouping: items, by: \.itemIndex)
        let pbItems = grouped.sorted { $0.key < $1.key }.map { (_, groupItems) -> NSPasteboardItem in
            let pbItem = NSPasteboardItem()
            for item in groupItems {
                pbItem.setData(item.data, forType: NSPasteboard.PasteboardType(rawValue: item.type))
            }
            return pbItem
        }
        pasteboard.writeObjects(pbItems)
    }

    func setString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func simulatePaste() async {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: UInt64(pasteDelay * 1_000_000_000))
    }
}
