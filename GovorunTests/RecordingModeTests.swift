import XCTest
@testable import Govorun

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

    func test_description() {
        XCTAssertFalse(RecordingMode.pushToTalk.description.isEmpty)
        XCTAssertFalse(RecordingMode.toggle.description.isEmpty)
    }

    func test_allCases() {
        XCTAssertEqual(RecordingMode.allCases, [.pushToTalk, .toggle])
    }
}
