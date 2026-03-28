import CryptoKit
@testable import Govorun
import XCTest

// MARK: - Mock

final class MockSuperModelDownloader: SuperModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SuperModelDownloadState = .idle

    var state: SuperModelDownloadState {
        lock.withLock { _state }
    }

    var isActive: Bool {
        switch state {
        case .checkingExisting, .downloading, .verifying: true
        default: false
        }
    }

    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)?

    var downloadCalled = false
    var cancelCalled = false
    var clearCalled = false
    var restoreCalled = false
    var lastSpec: SuperModelDownloadSpec?

    func download(from spec: SuperModelDownloadSpec) async {
        downloadCalled = true
        lastSpec = spec
    }

    func cancel() {
        cancelCalled = true
    }

    func clearPartialDownload(for spec: SuperModelDownloadSpec) {
        clearCalled = true
    }

    func restoreStateFromDisk(for spec: SuperModelDownloadSpec) {
        restoreCalled = true
    }

    @MainActor
    func simulateStateChange(_ newState: SuperModelDownloadState) {
        lock.withLock { _state = newState }
        onStateChanged?(newState)
    }
}

// MARK: - Tests

final class SuperModelDownloadManagerTests: XCTestCase {
    func test_mock_initial_state_is_idle() {
        let mock = MockSuperModelDownloader()
        XCTAssertEqual(mock.state, .idle)
        XCTAssertFalse(mock.isActive)
    }

    @MainActor
    func test_mock_simulate_downloading_sets_isActive() async {
        let mock = MockSuperModelDownloader()
        await mock.simulateStateChange(.downloading(progress: 0.5, downloadedBytes: 100, totalBytes: 200))
        XCTAssertTrue(mock.isActive)
    }

    @MainActor
    func test_mock_callback_fires_on_state_change() async {
        let mock = MockSuperModelDownloader()
        var receivedState: SuperModelDownloadState?
        mock.onStateChanged = { state in
            receivedState = state
        }
        await mock.simulateStateChange(.completed)
        XCTAssertEqual(receivedState, .completed)
    }

    func test_download_spec_equality() throws {
        let spec1 = try SuperModelDownloadSpec(
            url: XCTUnwrap(URL(string: "https://example.com/model.gguf")),
            destination: URL(fileURLWithPath: "/tmp/model.gguf"),
            expectedSHA256: "abc123",
            expectedSize: 1_000
        )
        let spec2 = spec1
        XCTAssertEqual(spec1, spec2)
    }

    func test_error_descriptions_not_empty() throws {
        let errors: [SuperModelDownloadError] = [
            .insufficientDiskSpace(required: 6_000_000_000, available: 1_000_000_000),
            .integrityCheckFailed,
            .networkError("timeout"),
            .fileSystemError("permission denied"),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
        }
    }
}

// MARK: - Helpers

@MainActor
private final class StatesBox {
    var states: [SuperModelDownloadState] = []
    func append(_ state: SuperModelDownloadState) {
        states.append(state)
    }
}

// MARK: - SuperModelDownloadManager Tests

final class SuperModelDownloadManagerImplTests: XCTestCase {
    private var tempDir: URL!
    private var spec: SuperModelDownloadSpec!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("govorun-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        spec = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "abc123def456",
            expectedSize: 1_000
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var partialPath: URL {
        spec.destination.appendingPathExtension("partial")
    }

    private var metaPath: URL {
        spec.destination.appendingPathExtension("partial.meta")
    }

    func test_restore_no_partial_stays_idle() {
        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_restore_partial_without_meta_stays_idle() throws {
        try Data("partial data".utf8).write(to: partialPath)
        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_restore_partial_with_matching_meta_becomes_partialReady() throws {
        let partialData = Data(repeating: 0, count: 500)
        try partialData.write(to: partialPath)

        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 500
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .partialReady(downloadedBytes: 500, totalBytes: spec.expectedSize))
    }

    func test_restore_partial_with_mismatched_sha_deletes_and_stays_idle() throws {
        try Data("partial data".utf8).write(to: partialPath)

        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: "wrong-sha",
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 12
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaPath.path))
    }

    func test_clear_removes_partial_and_meta() throws {
        try Data("data".utf8).write(to: partialPath)
        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 4
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.clearPartialDownload(for: spec)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaPath.path))
    }

    func test_clear_on_nonexistent_files_does_not_crash() {
        let manager = SuperModelDownloadManager()
        manager.clearPartialDownload(for: spec)
    }

    // MARK: - Fast path

    func test_download_existing_file_with_correct_sha_completes_immediately() async throws {
        let content = Data("test model content for sha256 verification".utf8)
        try content.write(to: spec.destination)

        let sha256 = SHA256.hash(data: content)
            .map { String(format: "%02x", $0) }
            .joined()

        let specWithSHA = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: sha256,
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        let statesBox = StatesBox()
        manager.onStateChanged = { state in
            statesBox.append(state)
        }

        await manager.download(from: specWithSHA)
        try? await Task.sleep(for: .milliseconds(100))

        let captured = await statesBox.states
        XCTAssertTrue(captured.contains(.checkingExisting))
        // state is set synchronously via lock, safe to read directly
        XCTAssertEqual(manager.state, .completed)
    }

    func test_download_existing_file_with_wrong_sha_does_not_complete() async throws {
        let content = Data("some data".utf8)
        try content.write(to: spec.destination)

        let specWithWrongSHA = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: "definitely-wrong-sha256",
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        await manager.download(from: specWithWrongSHA)
        XCTAssertNotEqual(manager.state, .completed)
    }

    // MARK: - Disk space

    func test_download_insufficient_disk_space_fails() async {
        let hugeSpec = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: Int64.max
        )

        let manager = SuperModelDownloadManager()
        await manager.download(from: hugeSpec)

        if case .failed(.insufficientDiskSpace) = manager.state {
            // OK
        } else {
            XCTFail("Ожидался .failed(.insufficientDiskSpace), получен \(manager.state)")
        }
    }

    // MARK: - SHA256

    func test_sha256_computation_is_correct() {
        let data = Data("hello world".utf8)
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        let hash = SuperModelDownloadManager.sha256(of: data)
        XCTAssertEqual(hash, expected)
    }

    // MARK: - SHA256 verification

    func test_verify_correct_sha_renames_to_destination() throws {
        let content = Data("verified model data".utf8)
        let sha = SuperModelDownloadManager.sha256(of: content)
        let partial = tempDir.appendingPathComponent("model.gguf.partial")
        try content.write(to: partial)
        let verifySpec = try SuperModelDownloadSpec(
            url: XCTUnwrap(URL(string: "https://example.com/model.gguf")),
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: sha, expectedSize: Int64(content.count)
        )
        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        switch result {
        case .success:
            XCTAssertTrue(FileManager.default.fileExists(atPath: verifySpec.destination.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        case .failure(let error):
            XCTFail("Ожидался success, получен \(error)")
        }
    }

    func test_verify_wrong_sha_returns_integrityCheckFailed() throws {
        let content = Data("bad data".utf8)
        let partial = tempDir.appendingPathComponent("model.gguf.partial")
        try content.write(to: partial)
        let verifySpec = try SuperModelDownloadSpec(
            url: XCTUnwrap(URL(string: "https://example.com/model.gguf")),
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "wrong-sha-256", expectedSize: Int64(content.count)
        )
        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        if case .failure(.integrityCheckFailed) = result {} else {
            XCTFail("Ожидался .integrityCheckFailed, получен \(result)")
        }
    }

    func test_verify_missing_partial_returns_fileSystemError() throws {
        let verifySpec = try SuperModelDownloadSpec(
            url: XCTUnwrap(URL(string: "https://example.com/model.gguf")),
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "abc", expectedSize: 100
        )
        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        if case .failure(.fileSystemError) = result {} else {
            XCTFail("Ожидался .fileSystemError, получен \(result)")
        }
    }

    func test_cancel_without_active_download_does_nothing() {
        let manager = SuperModelDownloadManager()
        manager.cancel()
        XCTAssertEqual(manager.state, .idle)
    }
}
