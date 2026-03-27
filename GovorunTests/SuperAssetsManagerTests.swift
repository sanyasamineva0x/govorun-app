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

    func test_check_withBothAssets_returnsInstalled() async {
        let checker = MockFileChecker()
        checker.executableFiles = ["/bundle/llama-server"]
        checker.readableFiles = ["/models/gigachat-gguf.gguf": 6_000_000_000]

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(manager.runtimeBinaryURL, URL(fileURLWithPath: "/bundle/llama-server"))
        XCTAssertEqual(manager.modelURL, URL(fileURLWithPath: "/models/gigachat-gguf.gguf"))
    }

    func test_check_withoutModel_returnsModelMissing() async {
        let checker = MockFileChecker()
        checker.executableFiles = ["/bundle/llama-server"]

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .modelMissing)
        XCTAssertEqual(manager.runtimeBinaryURL, URL(fileURLWithPath: "/bundle/llama-server"))
        XCTAssertNil(manager.modelURL)
    }

    func test_check_withoutBinary_returnsRuntimeMissing() async {
        let checker = MockFileChecker()
        checker.readableFiles = ["/models/gigachat-gguf.gguf": 6_000_000_000]

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .runtimeMissing)
        XCTAssertNil(manager.runtimeBinaryURL)
        XCTAssertNil(manager.modelURL)
    }

    func test_check_withTooSmallModel_returnsError() async {
        let checker = MockFileChecker()
        checker.executableFiles = ["/bundle/llama-server"]
        checker.readableFiles = ["/models/gigachat-gguf.gguf": 1_000]

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf"
        )

        let result = await manager.check()

        if case .error(let msg) = result {
            XCTAssertTrue(msg.contains("слишком маленький"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    func test_modelDiscovery_usesExactFilename() async {
        let checker = MockFileChecker()
        checker.executableFiles = ["/bundle/llama-server"]
        checker.readableFiles = [
            "/models/other-model.gguf": 6_000_000_000,
            "/models/custom-alias.gguf": 6_000_000_000,
        ]

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "custom-alias"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(manager.modelURL, URL(fileURLWithPath: "/models/custom-alias.gguf"))
    }

    func test_externalEndpoint_bypassesAssetCheck() async {
        let checker = MockFileChecker()

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf",
            baseURLString: "http://192.168.1.100:8080/v1"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .installed)
        XCTAssertNil(manager.runtimeBinaryURL)
        XCTAssertNil(manager.modelURL)
    }

    func test_localEndpoint_requiresAssets() async {
        let checker = MockFileChecker()

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf",
            baseURLString: "http://127.0.0.1:8080/v1"
        )

        let result = await manager.check()

        XCTAssertEqual(result, .runtimeMissing)
    }

    func test_resolvedPaths_nilWhenNotInstalled() async {
        let checker = MockFileChecker()

        let manager = SuperAssetsManager(
            fileChecker: checker,
            bundleResourcePath: "/bundle",
            modelsDirectory: "/models",
            modelAlias: "gigachat-gguf"
        )

        _ = await manager.check()

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
