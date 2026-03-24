import CoreGraphics
@testable import Govorun
import XCTest

final class ActivationKeyTests: XCTestCase {
    // MARK: - Equatable

    func test_modifier_equal() {
        let a = ActivationKey.modifier(.maskAlternate)
        let b = ActivationKey.modifier(.maskAlternate)
        XCTAssertEqual(a, b)
    }

    func test_modifier_notEqual_differentFlags() {
        let a = ActivationKey.modifier(.maskAlternate)
        let b = ActivationKey.modifier(.maskCommand)
        XCTAssertNotEqual(a, b)
    }

    func test_keyCode_equal() {
        let a = ActivationKey.keyCode(96) // F5
        let b = ActivationKey.keyCode(96)
        XCTAssertEqual(a, b)
    }

    func test_keyCode_notEqual() {
        let a = ActivationKey.keyCode(96)
        let b = ActivationKey.keyCode(97)
        XCTAssertNotEqual(a, b)
    }

    func test_combo_equal() {
        let a = ActivationKey.combo(modifiers: .maskCommand, keyCode: 40) // Cmd+K
        let b = ActivationKey.combo(modifiers: .maskCommand, keyCode: 40)
        XCTAssertEqual(a, b)
    }

    func test_combo_notEqual_differentKey() {
        let a = ActivationKey.combo(modifiers: .maskCommand, keyCode: 40)
        let b = ActivationKey.combo(modifiers: .maskCommand, keyCode: 41)
        XCTAssertNotEqual(a, b)
    }

    func test_combo_notEqual_differentModifiers() {
        let a = ActivationKey.combo(modifiers: .maskCommand, keyCode: 40)
        let b = ActivationKey.combo(modifiers: .maskShift, keyCode: 40)
        XCTAssertNotEqual(a, b)
    }

    func test_crossCase_notEqual() {
        let a = ActivationKey.modifier(.maskAlternate)
        let b = ActivationKey.keyCode(58) // Option keycode
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable roundtrip

    func test_codable_modifier_roundtrip() throws {
        let original = ActivationKey.modifier(.maskAlternate)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActivationKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codable_keyCode_roundtrip() throws {
        let original = ActivationKey.keyCode(96)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActivationKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codable_combo_roundtrip() throws {
        let original = ActivationKey.combo(modifiers: [.maskCommand, .maskShift], keyCode: 40)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActivationKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Codable fallback

    func test_codable_fallback_emptyJson() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActivationKey.self, from: json)
        XCTAssertEqual(decoded, .default)
        XCTAssertEqual(decoded, .modifier(.maskAlternate))
    }

    func test_codable_fallback_unknownType() throws {
        let json = #"{"type":"unknown"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActivationKey.self, from: json)
        XCTAssertEqual(decoded, .default)
    }

    // MARK: - displayName

    func test_displayName_option() {
        XCTAssertEqual(ActivationKey.modifier(.maskAlternate).displayName, "⌥")
    }

    func test_displayName_command() {
        XCTAssertEqual(ActivationKey.modifier(.maskCommand).displayName, "⌘")
    }

    func test_displayName_control() {
        XCTAssertEqual(ActivationKey.modifier(.maskControl).displayName, "⌃")
    }

    func test_displayName_shift() {
        XCTAssertEqual(ActivationKey.modifier(.maskShift).displayName, "⇧")
    }

    func test_displayName_multiModifier_shiftCommand() {
        // Apple HIG: ⌃ ⌥ ⇧ ⌘ — тест Shift+Cmd
        let flags = CGEventFlags([.maskShift, .maskCommand])
        XCTAssertEqual(ActivationKey.modifier(flags).displayName, "⇧⌘")
    }

    func test_displayName_F1() {
        // F1 = keycode 122
        XCTAssertEqual(ActivationKey.keyCode(122).displayName, "F1")
    }

    func test_displayName_letterA() {
        // A = keycode 0
        XCTAssertEqual(ActivationKey.keyCode(0).displayName, "A")
    }

    func test_displayName_combo_cmdK() {
        // K = keycode 40
        XCTAssertEqual(ActivationKey.combo(modifiers: .maskCommand, keyCode: 40).displayName, "⌘K")
    }

    func test_displayName_combo_shiftCmdK() {
        let flags = CGEventFlags([.maskShift, .maskCommand])
        XCTAssertEqual(ActivationKey.combo(modifiers: flags, keyCode: 40).displayName, "⇧⌘K")
    }

    // MARK: - Default

    func test_default_isOptionModifier() {
        XCTAssertEqual(ActivationKey.default, .modifier(.maskAlternate))
    }

    // MARK: - Вспомогательные методы (доступность)

    func test_modifierGlyphs_accessible() {
        // Метод должен быть доступен (не private) — нужен KeyRecorderView
        let glyph = ActivationKey.modifierGlyphs(.maskAlternate)
        XCTAssertEqual(glyph, "⌥")
    }

    func test_keyName_accessible() {
        let name = ActivationKey.keyName(122) // F1
        XCTAssertEqual(name, "F1")
    }
}
