# Testing

Reference: `GovorunTests/`, `worker/test_server.py`, `.github/workflows/tests.yml`, `Govorun.xctestplan`.

---

## Frameworks

| Layer | Framework | Command |
|---|---|---|
| Swift | XCTest | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| Python worker | pytest | `cd worker && python3 -m pytest test_server.py -v` |

No third-party Swift test frameworks (Quick/Nimble etc.) — pure XCTest throughout.

---

## Test Counts

- **986 Swift test functions** across 36 files in `GovorunTests/` (13 415 total lines).
- **23 Python test functions** in `worker/test_server.py`.
- `Govorun.xctestplan` skips `LLMQualityEvalTests` (slow eval suite, not in normal CI).

### Largest Swift test files

| File | Tests |
|---|---|
| `NumberNormalizerTests.swift` | 232 |
| `PipelineEngineTests.swift` | 102 |
| `ColdStartUITests.swift` | 56 |
| `SnippetEngineTests.swift` | 51 |
| `ASRWorkerManagerTests.swift` | 45 |
| `SettingsStoreTests.swift` | 29 |
| `TextInserterTests.swift` | 28 |
| `ErrorClassifierTests.swift` | 28 |
| `ActivationKeyMonitorTests.swift` | 28 |
| `ToggleRecoveryTests.swift` | 26 |

---

## Test File Structure

Each test file follows a consistent layout:

1. Imports (`@testable import Govorun`, `import XCTest`, optional `import SwiftData`)
2. Local mock classes (if needed by this file only)
3. One or more `XCTestCase` subclasses, each marked `final`
4. Test methods named `test_<subject>_<condition>` (snake_case after the `test_` prefix)
5. `MARK: -` sections group related test cases within a class

Example pattern from `GovorunTests/LocalSTTClientTests.swift`:

```swift
@testable import Govorun
import XCTest

final class LocalSTTClientTests: XCTestCase {
    // MARK: - parseResponse: успех
    func test_parseResponse_validText() throws { ... }

    // MARK: - parseResponse: ошибки worker
    func test_parseResponse_oomError() { ... }
}
```

### Test Method Naming Convention

```
test_<noun>_<condition_or_expected_result>
```

Examples:
- `test_initialState_isNotStarted`
- `test_check_withBothAssets_returnsInstalled`
- `test_parseResponse_oomError`
- `test_full_pipeline_mock`
- `test_trivial_text_skips_llm`
- `test_cancel_during_recording`

---

## Shared Mock Helpers

### `GovorunTests/TestHelpers.swift`

Contains the two core mocks used across most tests:

```swift
final class MockSTTClient: STTClient, @unchecked Sendable {
    var recognizeResult: STTResult?
    var recognizeError: Error?
    private(set) var recognizeCalls: [(audioData: Data, hints: [String])] = []
    private let lock = NSLock()
    // implements STTClient.recognize(audioData:hints:) async throws
}

final class MockLLMClient: LLMClient, @unchecked Sendable {
    var normalizeResult: String?
    var normalizeError: Error?
    private(set) var normalizeCalls: [(text: String, mode: TextMode, hints: NormalizationHints)] = []
    private let lock = NSLock()
    // implements LLMClient.normalize(_:mode:hints:) async throws
}
```

### Full Mock Inventory

| Mock Class | Protocol | Defined In |
|---|---|---|
| `MockSTTClient` | `STTClient` | `TestHelpers.swift` |
| `MockLLMClient` | `LLMClient` | `TestHelpers.swift` |
| `MockAudioRecording` | `AudioRecording` | `PipelineEngineTests.swift` |
| `MockSnippetEngine` | `SnippetMatching` | `PipelineEngineTests.swift` |
| `MockEventMonitoring` | `EventMonitoring` | `SessionManagerTests.swift` |
| `MockSessionDelegate` | `SessionManagerDelegate` | `SessionManagerTests.swift` |
| `MockAccessibility` | `AccessibilityProviding` | `TextInserterTests.swift` |
| `MockAXElement` | `AXFocusedElementProtocol` | `TextInserterTests.swift` |
| `MockClipboard` | `ClipboardProviding` | `TextInserterTests.swift` |
| `MockAnalyticsCollector` | `AnalyticsEmitting` | `PostInsertionMonitorTests.swift` |
| `MockFocusedTextReader` | `FocusedTextReading` | `PostInsertionMonitorTests.swift` |
| `MockFrontmostAppProvider` | `FrontmostAppProviding` | `PostInsertionMonitorTests.swift` |
| `MockGlobalKeyMonitorProvider` | `GlobalKeyMonitorProviding` | `PostInsertionMonitorTests.swift` |
| `MockSuperModelDownloader` | `SuperModelDownloading` | `SuperModelDownloadManagerTests.swift` |
| `MockSuperAssetsManager` | `SuperAssetsManaging` | `ColdStartUITests.swift` |
| `MockLLMRuntimeManager` | `LLMRuntimeManaging` | `ColdStartUITests.swift` |
| `MockWorkspaceProvider` | `WorkspaceProviding` | `AppContextEngineTests.swift` |
| `MockAppModeOverrides` | `AppModeOverriding` | `AppContextEngineTests.swift` |
| `MockASRWorkerManager` | `ASRWorkerManaging` | `ASRWorkerManagerTests.swift` |
| `MockAudioCapture` | `AudioRecording` | `AudioCaptureTests.swift` |
| `MockAudioCaptureDelegate` | `AudioCaptureDelegate` | `AudioCaptureTests.swift` |
| `MockSoundPlayer` | `SoundPlaying` | `PolishTests.swift` |
| `MockFileChecker` | `FileChecking` | `SuperAssetsManagerTests.swift` |
| `MockLLMRuntimeProcess` | `LLMRuntimeProcessControlling` | `LLMRuntimeManagerTests.swift` |
| `MockURLProtocol` | `URLProtocol` | `LocalLLMClientTests.swift` |

Production no-op:
- `NoOpAnalyticsService: AnalyticsEmitting` — `Core/AnalyticsEmitting.swift` (used in integration tests and as default wiring).
- `PlaceholderLLMClient: LLMClient` — `Services/LLMClient.swift` (placeholder, throws on call).

---

## Mock Design Patterns

### Call Recorder Pattern

All mocks record their calls with `private(set)` arrays protected by `NSLock`:

```swift
private(set) var recognizeCalls: [(audioData: Data, hints: [String])] = []
private let lock = NSLock()

func recognize(audioData: Data, hints: [String]) async throws -> STTResult {
    lock.lock()
    recognizeCalls.append((audioData, hints))
    lock.unlock()
    ...
}
```

Tests assert: `XCTAssertEqual(mockSTT.recognizeCalls.first?.hints, [])`.

### Result / Error Injection Pattern

```swift
var recognizeResult: STTResult?
var recognizeError: Error?

// In func: throw error first, then return result or throw noResult
```

### Controlled Continuation Pattern (for async timing tests)

`ControlledSTTClient` in `IntegrationTests.swift` suspends until explicitly resumed:

```swift
final class ControlledSTTClient: STTClient, @unchecked Sendable {
    func recognize(...) async throws -> STTResult {
        try await withCheckedThrowingContinuation { cont in
            lock.lock(); self.continuation = cont; lock.unlock()
        }
    }
    func complete(with result: STTResult) { ... cont?.resume(returning: result) }
    func fail(with error: Error) { ... cont?.resume(throwing: error) }
}
```

Used to test race conditions: assert `.processing` state then complete STT.

### Simulate Pattern

Event-emitting mocks have `simulate*` helpers:

```swift
// MockEventMonitoring
func simulateOptionDown() { flagsHandlers.forEach { $0(.maskAlternate) } }
func simulateKeyDown(keyCode: UInt16 = 0) { keyDownHandlers.forEach { $0(keyCode) } }

// MockFrontmostAppProvider
func simulateAppSwitch(to bundleId: String) { bundleIdToReturn = bundleId; activationHandler?() }

// MockSuperModelDownloader
@MainActor
func simulateStateChange(_ newState: SuperModelDownloadState) {
    lock.withLock { _state = newState }
    onStateChanged?(newState)
}
```

### State Collector Pattern

For multi-step state transition tests (e.g. `ASRWorkerManagerTests`):

```swift
private final class StateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [WorkerState] = []
    func append(_ state: WorkerState) { lock.lock(); _states.append(state); lock.unlock() }
    var states: [WorkerState] { lock.lock(); defer { lock.unlock() }; return _states }
}
```

### URLProtocol Stub Pattern (HTTP mocking)

`LocalLLMClientTests.swift` uses a custom `MockURLProtocol: URLProtocol` injected via `URLSessionConfiguration.protocolClasses`:

```swift
MockURLProtocol.requestHandler = { request in
    if request.url?.path == "/v1/models" {
        return HTTPStubResponse(statusCode: 200, body: #"{"data":[{"id":"gigachat-gguf"}]}"#)
    }
    ...
}
```

### Real Unix Socket Pattern

`LocalSTTClientTests.swift` spins up a real server in `DispatchQueue.global()` for IPC tests:

```swift
private func makeTestServer(socketPath: String, responseJSON: String) -> (serverFD: Int32, serverReady: DispatchSemaphore)
```

Tests call `ready.wait()` then `try await Task.sleep(nanoseconds: 10_000_000)` before connecting.

---

## Factory Helpers

### `makeTestAppState` (IntegrationTests.swift)

Full wiring factory annotated `@MainActor`. Returns `(AppState, MockAudioRecording, MockEventMonitoring, MockSuperModelDownloader)`.

Key parameters with defaults:
- `mockAudio: MockAudioRecording = MockAudioRecording()`
- `sttClient: STTClient? = nil` (falls back to `MockSTTClient` with `recognizeResult = STTResult(text: "тест")`)
- `llmClient: LLMClient? = nil` (falls back to `MockLLMClient` with `normalizeResult = "Тест."`)
- `accessibility: MockAccessibility = MockAccessibility()`
- `clipboard: MockClipboard = MockClipboard()`
- `recordingMode: RecordingMode = .pushToTalk`
- `productMode: ProductMode = .superMode`

Uses an isolated `UserDefaults(suiteName: "com.govorun.integration-test.\(UUID().uuidString)")` to prevent cross-test pollution.

### `makePipeline` (PipelineEngineTests.swift)

```swift
private func makePipeline(
    audio: MockAudioRecording = MockAudioRecording(),
    stt: MockSTTClient = MockSTTClient(),
    llm: MockLLMClient = MockLLMClient(),
    snippets: MockSnippetEngine? = nil,
    saveAudioFile: (@Sendable (Data, UUID) throws -> String)? = nil
) -> (PipelineEngine, MockAudioRecording, MockSTTClient, MockLLMClient)
```

### `makeStore()` (DictionaryStoreTests.swift, HistoryStoreTests.swift, SnippetEngineTests.swift)

```swift
private func makeStore() throws -> DictionaryStore {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DictionaryEntry.self, configurations: config)
    return DictionaryStore(modelContext: ModelContext(container))
}
```

### `makeService()` (AnalyticsServiceTests.swift)

Returns `(AnalyticsService, ModelContainer)` with in-memory container.

### `makeManager` + `makeExecutableFile` + `makeModelFile` (LLMRuntimeManagerTests.swift)

Creates temp executable files and model files (padded to >100 MB minimum threshold) for `LLMRuntimeManager` tests without touching real disk assets.

---

## TDD Workflow

Mandated in `CLAUDE.md`/`AGENTS.md`: **red → green → refactor**.

- Write failing test first.
- Never test with real Python worker or real ML models — always mock at the protocol boundary.
- Real models and worker are `.gitignore`d and not available in CI test runs.

---

## Integration Tests

`GovorunTests/IntegrationTests.swift` tests the full `AppState` wiring:

- Full pipeline: hotkey down → `MockAudioRecording` → `MockSTTClient` → `MockLLMClient` → `MockAccessibility` (AX insert)
- Uses `Task.sleep(nanoseconds:)` waits to let async pipelines complete (600ms min processing display + margin → typically 800ms total wait)
- Tests both `.pushToTalk` and `.toggle` recording modes
- Tests cancel during recording, cancel during processing, cancel during `minProcessingDisplay`
- Tests clipboard fallback when `accessibility.focusedElement == nil`
- Tests `DictionaryWiringTests` with real `ModelContainer` (in-memory) to verify replacements pass through to LLM hints
- Asserts on `appState.lastResult?.normalizedText`, `appState.lastResult?.normalizationPath`, `mockLLM.normalizeCalls.count`

---

## Python Worker Tests

**File:** `worker/test_server.py`
**Framework:** pytest
**23 test functions**

Key patterns:

- `MockModel` / `MockVAD` / `OOMModel` / `CrashModel` — plain Python classes, no real ONNX
- `worker_server` pytest fixture runs the worker loop in a background thread (not the real `server.py` main, but the same handle-connection logic), communicates through `~/.govorun/test_worker.sock`
- `make_wav_file()` helper creates real valid WAV files with silence for happy-path tests
- `make_corrupt_file()` creates non-WAV bytes for error-path tests
- `send_request(request, socket_path, timeout)` utility sends JSON, reads response, closes connection
- `send_raw(raw_bytes)` for malformed input tests
- Known flaky test: `test_stop_then_start_relaunches_worker` — race condition, documented non-blocker

---

## CI Pipeline

### `tests.yml` — runs on every PR to main and every push to main

```
swift-tests:   runs-on: macos-15
  xcodebuild test -scheme Govorun -destination 'platform=macOS'

python-tests:  runs-on: macos-14
  cd worker && python -m pytest test_server.py -v
```

No `xcodegen generate` step in tests.yml — the committed `.xcodeproj` is used directly.

### `release.yml` — runs on `v*` tags

Full pipeline including tests before building DMG:

1. Validate `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` match tag
2. Cache and fetch Python.framework (key: hash of `fetch-python-framework.sh`)
3. Cache and fetch wheels (key: hash of `requirements.txt` + `download-wheels.sh`)
4. Cache and build `Helpers/llama-server` arm64 static binary (key: hash of `build-llama-server.sh`)
5. Validate `llama-server` is arm64 and has only system dylib dependencies
6. `xcodegen generate`
7. **Run all Swift tests** — same command as tests.yml
8. Build unsigned DMG
9. Sign with Sparkle EdDSA (`SPARKLE_PRIVATE_KEY` secret)
10. Create GitHub Release, update `appcast.xml`, update Homebrew Cask

### Test Plan

`Govorun.xctestplan` at repo root:
- `testTimeoutsEnabled: false` — integration tests use real `Task.sleep` waits without a hard timeout
- `skippedTests: ["LLMQualityEvalTests"]` — quality eval suite excluded from CI
