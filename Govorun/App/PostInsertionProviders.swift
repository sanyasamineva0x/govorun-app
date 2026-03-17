import Cocoa

// MARK: - System implementation: FrontmostAppProviding

final class SystemFrontmostAppProvider: FrontmostAppProviding {
    func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func addActivationObserver(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
}

// MARK: - System implementation: FocusedTextReading

final class SystemFocusedTextReader: FocusedTextReading {
    func readFocusedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }

        var value: CFTypeRef?
        // CFTypeRef → AXUIElement: as? не работает для CF типов, используем CFGetTypeID guard
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let axElement = unsafeBitCast(element, to: AXUIElement.self)
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value)
        guard valueResult == .success, let textValue = value as? String else { return nil }

        return textValue
    }
}

// MARK: - System implementation: GlobalKeyMonitorProviding

final class SystemGlobalKeyMonitorProvider: GlobalKeyMonitorProviding {
    func addGlobalKeyDownMonitor(handler: @escaping (GlobalKeyEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { nsEvent in
            var flags = GlobalKeyEvent.ModifierFlags(rawValue: 0)
            if nsEvent.modifierFlags.contains(.command) {
                flags.insert(.command)
            }
            if nsEvent.modifierFlags.contains(.shift) {
                flags.insert(.shift)
            }
            let event = GlobalKeyEvent(keyCode: nsEvent.keyCode, modifierFlags: flags)
            handler(event)
        }
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}
