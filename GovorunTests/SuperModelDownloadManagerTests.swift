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
