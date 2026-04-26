@testable import Govorun
import XCTest

@MainActor
final class AppStateCloudShimTests: XCTestCase {
    // MARK: - Helper: минимальный AppState для shim-тестов

    private func makeAppState(
        credentialStore: CredentialStoring,
        authService: AuthService? = nil
    ) -> (AppState, SettingsStore) {
        let suiteName = "com.govorun.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)

        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: .default,
                recordingMode: .pushToTalk,
                eventMonitor: MockEventMonitoring()
            ),
            sessionManager: SessionManager(),
            pipelineEngine: PipelineEngine(
                audioCapture: MockAudioRecording(),
                sttClient: MockSTTClient(),
                llmClient: MockLLMClient(),
                snippetEngine: SnippetEngine()
            ),
            textInserter: TextInserterEngine(
                accessibility: MockAccessibility(),
                clipboard: MockClipboard()
            ),
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            credentialStore: credentialStore
        )

        if let authService {
            appState.authServiceFactory = { authService }
        }

        return (appState, settings)
    }

    // MARK: - saveCloudCredentials

    func test_saveCloudCredentials_writesToStore_and_flipsCloudAvailableTrue() throws {
        let store = MockCredentialStore()
        let (appState, _) = makeAppState(credentialStore: store)
        XCTAssertFalse(appState.cloudAvailable, "пустой store — cloudAvailable=false")

        try appState.saveCloudCredentials(clientId: "abc", clientSecret: "xyz")

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls.first?.clientId, "abc")
        XCTAssertEqual(store.saveCalls.first?.secret, "xyz")
        XCTAssertTrue(appState.cloudAvailable)
    }

    // MARK: - deleteCloudCredentials

    func test_deleteCloudCredentials_clearsStore_and_flipsCloudAvailableFalse_keepsConsent() throws {
        let store = MockCredentialStore()
        try store.save(clientId: "abc", clientSecret: "xyz")
        let (appState, settings) = makeAppState(credentialStore: store)
        settings.cloudConsentAcceptedAt = Date(timeIntervalSince1970: 1_735_000_000)
        XCTAssertTrue(appState.cloudAvailable)

        try appState.deleteCloudCredentials()

        XCTAssertNil(store.get())
        XCTAssertFalse(appState.cloudAvailable)
        XCTAssertNotNil(settings.cloudConsentAcceptedAt, "consent не очищается при удалении ключей — D-07")
    }

    // MARK: - probeCloudConnection

    func test_probeCloudConnection_returnsSuccess_whenTokenFetched() async throws {
        let store = MockCredentialStore()
        try store.save(clientId: "abc", clientSecret: "xyz")
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "test-token"
        let (appState, _) = makeAppState(credentialStore: store, authService: mockAuth)

        let result = await appState.probeCloudConnection()

        guard case .success = result else {
            XCTFail("Ожидался .success, получен \(result)")
            return
        }
        XCTAssertEqual(mockAuth.callCount, 1)
    }

    func test_probeCloudConnection_returnsFailure_whenAuthErrorThrown() async throws {
        let store = MockCredentialStore()
        try store.save(clientId: "abc", clientSecret: "xyz")
        let mockAuth = MockAuthService()
        mockAuth.tokenError = AuthError.invalidResponse(statusCode: 401)
        let (appState, _) = makeAppState(credentialStore: store, authService: mockAuth)

        let result = await appState.probeCloudConnection()

        guard case .failure(let authError) = result else {
            XCTFail("Ожидался .failure, получен \(result)")
            return
        }
        XCTAssertEqual(authError, AuthError.invalidResponse(statusCode: 401))
    }

    // MARK: - TEST-01: Error-path propagation

    func test_saveCloudCredentials_propagatesStoreError_keepsCloudAvailableFalse() {
        let store = MockCredentialStore()
        store.saveError = CredentialStoreError.saveFailed(-25_299)
        let (appState, _) = makeAppState(credentialStore: store)
        XCTAssertFalse(appState.cloudAvailable, "пустой store + saveError — cloudAvailable=false")

        XCTAssertThrowsError(try appState.saveCloudCredentials(clientId: "a", clientSecret: "b")) { error in
            XCTAssertEqual(error as? CredentialStoreError, .saveFailed(-25_299))
        }

        XCTAssertFalse(appState.cloudAvailable, "при ошибке save cloudAvailable не должен флипаться на true")
    }

    func test_deleteCloudCredentials_propagatesStoreError() throws {
        let store = MockCredentialStore()
        try store.save(clientId: "abc", clientSecret: "xyz")
        store.deleteError = CredentialStoreError.deleteFailed(-25_300)
        let (appState, _) = makeAppState(credentialStore: store)

        XCTAssertThrowsError(try appState.deleteCloudCredentials()) { error in
            XCTAssertEqual(error as? CredentialStoreError, .deleteFailed(-25_300))
        }
    }

    func test_probeCloudConnection_wrapsNonAuthErrorIn_networkError() async throws {
        struct UnexpectedError: Error {}

        let store = MockCredentialStore()
        try store.save(clientId: "abc", clientSecret: "xyz")
        let mockAuth = MockAuthService()
        mockAuth.tokenError = UnexpectedError()
        let (appState, _) = makeAppState(credentialStore: store, authService: mockAuth)

        let result = await appState.probeCloudConnection()

        guard case .failure(let authError) = result,
              case .networkError = authError
        else {
            XCTFail("Ожидался .failure(.networkError), получен \(result)")
            return
        }
    }
}
