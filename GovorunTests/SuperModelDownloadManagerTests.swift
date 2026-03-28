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
}
