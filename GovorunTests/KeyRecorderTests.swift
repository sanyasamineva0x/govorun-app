import CoreGraphics
@testable import Govorun
import XCTest

// MARK: - Equatable для тестов

extension KeyRecorderLogic.FlagsResult: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.awaitingRelease(let a), .awaitingRelease(let b)): a.rawValue == b.rawValue
        case (.finalized, .finalized): true
        case (.ignored, .ignored): true
        default: false
        }
    }
}

extension KeyRecorderLogic.KeyResult: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.keyCode(let a), .keyCode(let b)): a == b
        case (.combo(let am, let ak), .combo(let bm, let bk)): am.rawValue == bm.rawValue && ak == bk
        case (.cancel, .cancel): true
        case (.ignored, .ignored): true
        default: false
        }
    }
}

// MARK: - Тесты логики

final class KeyRecorderTests: XCTestCase {
    func test_flags_option_awaits_release() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: .maskAlternate, hasPendingModifier: false)
        XCTAssertEqual(result, .awaitingRelease(.maskAlternate))
    }

    func test_flags_command_awaits_release() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: .maskCommand, hasPendingModifier: false)
        XCTAssertEqual(result, .awaitingRelease(.maskCommand))
    }

    func test_flags_released_finalizes_modifier() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: CGEventFlags(), hasPendingModifier: true)
        XCTAssertEqual(result, .finalized)
    }

    func test_flags_released_without_pending_ignored() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: CGEventFlags(), hasPendingModifier: false)
        XCTAssertEqual(result, .ignored)
    }

    func test_keyDown_without_modifier_returns_keyCode() {
        let result = KeyRecorderLogic.mapKeyDown(keyCode: 96, currentFlags: CGEventFlags(), hasPendingModifier: false)
        XCTAssertEqual(result, .keyCode(96))
    }

    func test_keyDown_with_modifier_returns_combo() {
        let result = KeyRecorderLogic.mapKeyDown(keyCode: 40, currentFlags: .maskCommand, hasPendingModifier: true)
        XCTAssertEqual(result, .combo(modifiers: .maskCommand, keyCode: 40))
    }

    func test_escape_returns_cancel() {
        let result = KeyRecorderLogic.mapKeyDown(keyCode: 53, currentFlags: CGEventFlags(), hasPendingModifier: false)
        XCTAssertEqual(result, .cancel)
    }

    // MARK: - Дополнительные edge case

    func test_flags_control_awaits_release() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: .maskControl, hasPendingModifier: false)
        XCTAssertEqual(result, .awaitingRelease(.maskControl))
    }

    func test_flags_shift_awaits_release() {
        let result = KeyRecorderLogic.mapFlagsChanged(flags: .maskShift, hasPendingModifier: false)
        XCTAssertEqual(result, .awaitingRelease(.maskShift))
    }

    func test_escape_cancels_even_with_pending_modifier() {
        let result = KeyRecorderLogic.mapKeyDown(keyCode: 53, currentFlags: .maskCommand, hasPendingModifier: true)
        XCTAssertEqual(result, .cancel)
    }

    func test_keyDown_no_pending_modifier_but_flags_present_returns_keyCode() {
        // hasPendingModifier = false → игнорируем флаги, возвращаем keyCode
        let result = KeyRecorderLogic.mapKeyDown(keyCode: 40, currentFlags: .maskCommand, hasPendingModifier: false)
        XCTAssertEqual(result, .keyCode(40))
    }
}
