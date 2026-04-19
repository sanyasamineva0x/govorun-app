@testable import Govorun
import XCTest

// MARK: - Мок

final class MockNetworkAvailability: NetworkAvailabilityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _connected: Bool

    init(connected: Bool = true) {
        _connected = connected
    }

    var isCurrentlyConnected: Bool {
        lock.lock(); defer { lock.unlock() }; return _connected
    }

    func setConnected(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }; _connected = value
    }
}

// MARK: - Тесты протокола и мока

final class NetworkAvailabilityProvidingTests: XCTestCase {
    func test_networkMonitor_conforms_to_providing_protocol() {
        let monitor = NetworkMonitor()
        let provider: NetworkAvailabilityProviding = monitor
        _ = provider.isCurrentlyConnected
    }

    func test_mockNetworkAvailability_returns_configured_true() {
        let mock = MockNetworkAvailability(connected: true)
        XCTAssertTrue(mock.isCurrentlyConnected)
    }

    func test_mockNetworkAvailability_returns_configured_false() {
        let mock = MockNetworkAvailability(connected: false)
        XCTAssertFalse(mock.isCurrentlyConnected)
    }

    func test_mockNetworkAvailability_setConnected_updates_value() {
        let mock = MockNetworkAvailability(connected: false)
        XCTAssertFalse(mock.isCurrentlyConnected)
        mock.setConnected(true)
        XCTAssertTrue(mock.isCurrentlyConnected)
    }

    // MARK: - PipelineEngine принимает провайдер

    func test_pipelineEngine_accepts_network_availability_via_init() {
        let mock = MockNetworkAvailability(connected: true)
        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: MockSTTClient(),
            llmClient: MockLLMClient(),
            snippetEngine: nil,
            saveAudioFile: nil,
            deleteAudioFile: nil,
            networkAvailability: mock
        )
        _ = engine
    }

    func test_pipelineEngine_default_networkAvailability_is_nil_compile_check() {
        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: MockSTTClient(),
            llmClient: MockLLMClient()
        )
        _ = engine
    }

    func test_pipelineEngine_with_nil_provider_does_not_crash_in_startStop() async throws {
        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: MockSTTClient(),
            llmClient: MockLLMClient()
        )
        try engine.startRecording(sessionId: UUID())
        _ = try await engine.stopRecording()
    }
}
