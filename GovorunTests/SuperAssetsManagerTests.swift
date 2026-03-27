@testable import Govorun
import XCTest

final class SuperAssetsManagerTests: XCTestCase {
    func test_initialState_isUnknown() {
        let manager = SuperAssetsManager(
            fileChecker: MockFileChecker(),
            bundleResourcePath: "/fake/bundle",
            modelsDirectory: "/fake/models",
            modelAlias: "gigachat-gguf"
        )
        XCTAssertEqual(manager.state, .unknown)
        XCTAssertNil(manager.runtimeBinaryURL)
        XCTAssertNil(manager.modelURL)
    }
}

// MARK: - Mock

private final class MockFileChecker: FileChecking {
    var executableFiles: Set<String> = []
    var readableFiles: [String: UInt64] = [:]

    func isExecutableFile(atPath path: String) -> Bool {
        executableFiles.contains(path)
    }

    func isReadableFile(atPath path: String) -> Bool {
        readableFiles[path] != nil
    }

    func fileSize(atPath path: String) -> UInt64? {
        readableFiles[path]
    }
}
