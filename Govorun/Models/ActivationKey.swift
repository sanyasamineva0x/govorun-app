import CoreGraphics

// MARK: - Клавиша активации

/// Три способа задать клавишу активации: одиночный модификатор, обычная клавиша,
/// или комбинация модификатор+клавиша.
enum ActivationKey: Sendable {
    case modifier(CGEventFlags)
    case keyCode(UInt16)
    case combo(modifiers: CGEventFlags, keyCode: UInt16)
}

// MARK: - Equatable

extension ActivationKey: Equatable {
    static func == (lhs: ActivationKey, rhs: ActivationKey) -> Bool {
        switch (lhs, rhs) {
        case (.modifier(let a), .modifier(let b)):
            return a.rawValue == b.rawValue
        case (.keyCode(let a), .keyCode(let b)):
            return a == b
        case (.combo(let am, let ak), .combo(let bm, let bk)):
            return am.rawValue == bm.rawValue && ak == bk
        default:
            return false
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
              let type = try? container.decode(String.self, forKey: .type) else {
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
               let code = try? container.decode(UInt16.self, forKey: .keyCode) {
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
            return ActivationKey.modifierGlyphs(flags)
        case .keyCode(let code):
            return ActivationKey.keyName(code)
        case .combo(let flags, let code):
            return ActivationKey.modifierGlyphs(flags) + ActivationKey.keyName(code)
        }
    }

    /// Глифы модификаторов в порядке Apple HIG: ⌃ ⌥ ⇧ ⌘
    static func modifierGlyphs(_ flags: CGEventFlags) -> String {
        var result = ""
        if flags.rawValue & CGEventFlags.maskControl.rawValue != 0   { result += "⌃" }
        if flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { result += "⌥" }
        if flags.rawValue & CGEventFlags.maskShift.rawValue != 0     { result += "⇧" }
        if flags.rawValue & CGEventFlags.maskCommand.rawValue != 0   { result += "⌘" }
        return result
    }

    /// Название обычной клавиши по keycode (виртуальный keycode macOS)
    static func keyName(_ code: UInt16) -> String {
        switch code {
        // Функциональные клавиши
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        // Спецклавиши
        case 53:  return "Esc"
        case 36:  return "Return"
        case 48:  return "Tab"
        case 49:  return "Space"
        case 51:  return "Delete"
        case 57:  return "CapsLock"
        // Стрелки
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        // Буквы (QWERTY раскладка)
        case 0:   return "A"
        case 11:  return "B"
        case 8:   return "C"
        case 2:   return "D"
        case 14:  return "E"
        case 3:   return "F"
        case 5:   return "G"
        case 4:   return "H"
        case 34:  return "I"
        case 38:  return "J"
        case 40:  return "K"
        case 37:  return "L"
        case 46:  return "M"
        case 45:  return "N"
        case 31:  return "O"
        case 35:  return "P"
        case 12:  return "Q"
        case 15:  return "R"
        case 1:   return "S"
        case 17:  return "T"
        case 32:  return "U"
        case 9:   return "V"
        case 13:  return "W"
        case 7:   return "X"
        case 16:  return "Y"
        case 6:   return "Z"
        // Цифры
        case 29:  return "0"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 23:  return "5"
        case 22:  return "6"
        case 26:  return "7"
        case 28:  return "8"
        case 25:  return "9"
        // Неизвестный keycode
        default:  return "[\(code)]"
        }
    }
}
