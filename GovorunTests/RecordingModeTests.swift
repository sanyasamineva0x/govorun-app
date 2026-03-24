@testable import Govorun
import XCTest

final class RecordingModeTests: XCTestCase {
    func test_default_is_pushToTalk() {
        let mode = RecordingMode.pushToTalk
        XCTAssertEqual(mode.rawValue, "pushToTalk")
    }

    func test_codable_roundtrip_pushToTalk() throws {
        let original = RecordingMode.pushToTalk
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_codable_roundtrip_toggle() throws {
        let original = RecordingMode.toggle
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_title() {
        XCTAssertEqual(RecordingMode.pushToTalk.title, "Push to Talk")
        XCTAssertEqual(RecordingMode.toggle.title, "Toggle")
    }

    func test_subtitle() {
        XCTAssertFalse(RecordingMode.pushToTalk.subtitle.isEmpty)
        XCTAssertFalse(RecordingMode.toggle.subtitle.isEmpty)
    }

    func test_hint() {
        XCTAssertEqual(RecordingMode.pushToTalk.hint(key: "⌥"), "Зажмите ⌥ и говорите")
        XCTAssertEqual(RecordingMode.toggle.hint(key: "⌥"), "Нажмите ⌥ для записи")
    }

    func test_allCases() {
        XCTAssertEqual(RecordingMode.allCases, [.pushToTalk, .toggle])
    }
}
