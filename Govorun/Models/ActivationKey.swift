import CoreGraphics

// MARK: - Клавиша активации

/// Три способа задать клавишу активации: одиночный модификатор, обычная клавиша,
/// или комбинация модификатор+клавиша.
enum ActivationKey {
    case modifier(CGEventFlags)
    case keyCode(UInt16)
    case combo(modifiers: CGEventFlags, keyCode: UInt16)
}

// MARK: - Equatable

extension ActivationKey: Equatable {
    static func == (lhs: ActivationKey, rhs: ActivationKey) -> Bool {
        switch (lhs, rhs) {
        case (.modifier(let a), .modifier(let b)):
            a.rawValue == b.rawValue
        case (.keyCode(let a), .keyCode(let b)):
            a == b
        case (.combo(let am, let ak), .combo(let bm, let bk)):
            am.rawValue == bm.rawValue && ak == bk
        default:
            false
        }
    }
}

// MARK: - Codable

extension ActivationKey: Codable {
    /// Ключи JSON-кодирования
    private enum CodingKeys: String, CodingKey {
        case type, flags, keyCode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .modifier(let flags):
            try container.encode("modifier", forKey: .type)
            try container.encode(flags.rawValue, forKey: .flags)
        case .keyCode(let code):
            try container.encode("keyCode", forKey: .type)
            try container.encode(code, forKey: .keyCode)
        case .combo(let flags, let code):
            try container.encode("combo", forKey: .type)
            try container.encode(flags.rawValue, forKey: .flags)
            try container.encode(code, forKey: .keyCode)
        }
    }

    init(from decoder: Decoder) {
        // При любой ошибке декодирования — возвращаем значение по умолчанию
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let type = try? container.decode(String.self, forKey: .type)
        else {
            print("[Govorun] ActivationKey: не удалось декодировать контейнер, используем default")
            self = .default
            return
        }

        switch type {
        case "modifier":
            if let raw = try? container.decode(UInt64.self, forKey: .flags) {
                self = .modifier(CGEventFlags(rawValue: raw))
            } else {
                print("[Govorun] ActivationKey: modifier без flags, используем default")
                self = .default
            }
        case "keyCode":
            if let code = try? container.decode(UInt16.self, forKey: .keyCode) {
                self = .keyCode(code)
            } else {
                print("[Govorun] ActivationKey: keyCode без кода, используем default")
                self = .default
            }
        case "combo":
            if let raw = try? container.decode(UInt64.self, forKey: .flags),
               let code = try? container.decode(UInt16.self, forKey: .keyCode)
            {
                self = .combo(modifiers: CGEventFlags(rawValue: raw), keyCode: code)
            } else {
                print("[Govorun] ActivationKey: combo без flags/keyCode, используем default")
                self = .default
            }
        default:
            print("[Govorun] ActivationKey: неизвестный тип '\(type)', используем default")
            self = .default
        }
    }
}

// MARK: - Значение по умолчанию и отображение

extension ActivationKey {
    /// Клавиша по умолчанию — ⌥ Option
    static let `default`: ActivationKey = .modifier(.maskAlternate)

    /// Человекочитаемое название: "⌥", "F1", "⌘K", "⇧⌘K"
    var displayName: String {
        switch self {
        case .modifier(let flags):
            ActivationKey.modifierGlyphs(flags)
        case .keyCode(let code):
            ActivationKey.keyName(code)
        case .combo(let flags, let code):
            ActivationKey.modifierGlyphs(flags) + ActivationKey.keyName(code)
        }
    }

    /// Глифы модификаторов в порядке Apple HIG: ⌃ ⌥ ⇧ ⌘
    static func modifierGlyphs(_ flags: CGEventFlags) -> String {
        var result = ""
        if flags.rawValue & CGEventFlags.maskControl.rawValue != 0 { result += "⌃" }
        if flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { result += "⌥" }
        if flags.rawValue & CGEventFlags.maskShift.rawValue != 0 { result += "⇧" }
        if flags.rawValue & CGEventFlags.maskCommand.rawValue != 0 { result += "⌘" }
        return result
    }

    /// Название обычной клавиши по keycode (виртуальный keycode macOS)
    static func keyName(_ code: UInt16) -> String {
        switch code {
        // Функциональные клавиши
        case 122: "F1"
        case 120: "F2"
        case 99: "F3"
        case 118: "F4"
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 100: "F8"
        case 101: "F9"
        case 109: "F10"
        case 103: "F11"
        case 111: "F12"
        case 105: "F13"
        case 107: "F14"
        case 113: "F15"
        // Спецклавиши
        case 53: "Esc"
        case 36: "Return"
        case 48: "Tab"
        case 49: "Space"
        case 51: "Delete"
        case 57: "CapsLock"
        // Стрелки
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        // Буквы (QWERTY раскладка)
        case 0: "A"
        case 11: "B"
        case 8: "C"
        case 2: "D"
        case 14: "E"
        case 3: "F"
        case 5: "G"
        case 4: "H"
        case 34: "I"
        case 38: "J"
        case 40: "K"
        case 37: "L"
        case 46: "M"
        case 45: "N"
        case 31: "O"
        case 35: "P"
        case 12: "Q"
        case 15: "R"
        case 1: "S"
        case 17: "T"
        case 32: "U"
        case 9: "V"
        case 13: "W"
        case 7: "X"
        case 16: "Y"
        case 6: "Z"
        // Цифры
        case 29: "0"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 23: "5"
        case 22: "6"
        case 26: "7"
        case 28: "8"
        case 25: "9"
        // Неизвестный keycode
        default: "[\(code)]"
        }
    }
}
