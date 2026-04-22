# Phase 16: Tests — Pattern Map

**Mapped:** 2026-04-23
**Files analyzed:** ~6 expected (audit-driven; could be 0 new test files if coverage already sufficient + 2-3 benchmark scripts)
**Analogs found:** 100% — все целевые точки имеют конкретные образцы в репо.

---

## File Classification

Phase 16 — audit-first, поэтому точный list файлов определится в planner. Ниже — все возможные новые/модифицированные файлы и их классификация.

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `GovorunTests/SberAuthServiceTests.swift` (extend) | test | request-response (mock HTTP) | сам себя (extend) — `SberAuthServiceTests.swift` | exact |
| `GovorunTests/CloudLLMClientTests.swift` (extend) | test | request-response + multipart upload | сам себя (extend) — `CloudLLMClientTests.swift` | exact |
| `GovorunTests/CredentialStoreTests.swift` (extend) | test | CRUD (Keychain via mock) | сам себя (extend) — `CredentialStoreTests.swift` | exact |
| `GovorunTests/SberTrustPolicyTests.swift` (extend) | test | bundle-resource I/O + cert parsing | сам себя (extend) — `SberTrustPolicyTests.swift` | exact |
| `GovorunTests/AppStateCloudShimTests.swift` (extend) | test | event-driven + @MainActor | сам себя (extend) — `AppStateCloudShimTests.swift` | exact |
| `GovorunTests/CloudSettingsErrorMessageTests.swift` (extend) | test | pure transform (error → string) | сам себя (extend) — `CloudSettingsErrorMessageTests.swift` | exact |
| `scripts/benchmark-full-pipeline-helper.swift` (repair) | helper-binary | line-by-line stdin/stdout JSON | сам себя — структура корректна, скорее всего нужны мелкие правки под текущий `NormalizationPipeline.preflight/postflight` API | exact (self-repair) |
| `scripts/benchmark-llm-normalization.py` (extend `--mode cloud`) | benchmark | streaming HTTP (SSE) | сам себя (`request_completion()` lines 421–501) — добавить cloud branch с OAuth + multipart upload | exact (self-extend) |
| `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md` (create) | doc | n/a | `benchmarks/reports/*.md` если есть, иначе свободная форма | role-match / new |
| `.env.bench` (create, gitignored) | config | n/a | `worker/setup.sh` (env handling pattern) | partial |

---

## Pattern Assignments

### `GovorunTests/CloudLLMClientTests.swift` (test, request-response + multipart)

**Analog:** сам себя (extend существующий файл — образец-эталон для всех cloud HTTP-тестов).

**Imports pattern** (lines 1-2):
```swift
@testable import Govorun
import XCTest
```

**SequentialMockHTTPClient pattern** — встроенный private mock для последовательных HTTP-вызовов (upload → completions → retry). НЕ переносить в TestHelpers, оставить как private final class в каждом файле, где нужна последовательность. (lines 6-28):
```swift
private final class SequentialMockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    var responses: [(Data, URLResponse)] = []
    var errors: [Error?] = []
    private(set) var requests: [URLRequest] = []
    private var callIndex = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let index = callIndex
        callIndex += 1
        lock.unlock()

        if index < errors.count, let error = errors[index] {
            throw error
        }
        guard index < responses.count else {
            fatalError("SequentialMockHTTPClient: нет ответа для вызова \(index)")
        }
        return responses[index]
    }
}
```

**Response-builder helpers** (lines 39-73): factory-методы для `(Data, URLResponse)` пар — `makeUploadResponse`, `makeCompletionResponse`, `makeErrorResponse`. Если добавляются новые тесты с другим shape ответа — расширять этими же helpers, не дублировать создание `HTTPURLResponse(...)` в каждом тесте.

**Standard test setup pattern** (lines 75-91, plus inline-style in lines 96-108):
```swift
private func makeClient(
    authService: AuthService? = nil,
    httpClient: HTTPClient? = nil,
    configuration: CloudLLMConfiguration = CloudLLMConfiguration()
) -> CloudLLMClient {
    let auth = authService ?? {
        let mock = MockAuthService()
        mock.tokenResult = "mock-token"
        return mock
    }()
    let http = httpClient ?? MockHTTPClient()
    return CloudLLMClient(
        authService: auth,
        httpClient: httpClient,
        configuration: configuration
    )
}
```

**Async test + multipart body inspection pattern** (lines 95-140) — для CLOUD-01 / CLOUD-02 audit gap проверок:
```swift
func test_processAudio_uploadsWAVFile() async throws {
    let mockHTTP = SequentialMockHTTPClient()
    mockHTTP.responses = [makeUploadResponse(), makeCompletionResponse()]
    let mockAuth = MockAuthService()
    mockAuth.tokenResult = "mock-token"

    let client = CloudLLMClient(
        authService: mockAuth, httpClient: mockHTTP,
        configuration: CloudLLMConfiguration()
    )

    let audioData = Data([0x52, 0x49, 0x46, 0x46])
    _ = try await client.processAudio(
        audioData: audioData, superStyle: .normal, hints: makeHints()
    )

    let uploadRequest = mockHTTP.requests[0]
    XCTAssertEqual(uploadRequest.url?.path, "/api/v1/files")
    XCTAssertEqual(uploadRequest.httpMethod, "POST")
    let contentType = try XCTUnwrap(uploadRequest.value(forHTTPHeaderField: "Content-Type"))
    XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

    // ВАЖНО: для multipart с binary WAV — декодим body как .isoLatin1, не .utf8!
    let body = try XCTUnwrap(uploadRequest.httpBody)
    let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
    XCTAssertTrue(bodyString.contains("audio.wav"))
}
```

**Retry pattern** (lines 260-287):
```swift
func test_processAudio_retriesOnServerError() async throws {
    let mockHTTP = SequentialMockHTTPClient()
    mockHTTP.responses = [
        makeUploadResponse(),
        makeErrorResponse(statusCode: 500, url: "..."),
        makeCompletionResponse(content: "Success after retry"),
    ]
    // ВАЖНО: всегда задавать retryDelay: 0.01 чтобы тесты не тормозили
    let client = CloudLLMClient(
        authService: mockAuth, httpClient: mockHTTP,
        configuration: CloudLLMConfiguration(retryDelay: 0.01)
    )

    let result = try await client.processAudio(...)
    XCTAssertEqual(result, "Success after retry")
    XCTAssertEqual(mockHTTP.requests.count, 3)
}
```

**Error mapping pattern** (lines 387-410, 462-485):
```swift
func test_processAudio_mapsCredentialsNotFound() async throws {
    let mockAuth = MockAuthService()
    mockAuth.tokenError = AuthError.credentialsNotFound
    // ...
    do {
        _ = try await client.processAudio(...)
        XCTFail("Ожидалась ошибка")
    } catch let error as LLMError {
        XCTAssertEqual(error, .networkError("Cloud credentials not configured"))
    } catch {
        XCTFail("Ожидался LLMError, получен \(error)")
    }
}
```

**Test naming convention:**
- `test_<methodUnderTest>_<scenario>` — например `test_processAudio_retriesOnServerError`, `test_normalize_emptyTextReturnsEmpty`.
- MARK секции группируют по feature ID: `// MARK: - CLOUD-01: WAV upload via /files`, `// MARK: - CLOUD-06: timeout + retry`, `// MARK: - D-07: маппинг AuthError`.

**Coverage gap candidates для аудита:**
- Network timeout (URLError(.timedOut)) → `.timeout` mapping — нет теста, нужно добавить (использовать SequentialMockHTTPClient.errors)
- Empty `choices` array в response → `.parsingFailed` — проверить
- `attachments` field shape для multimodal completion с audio — спецификация Sber мог поменяться

---

### `GovorunTests/SberAuthServiceTests.swift` (test, request-response + token caching)

**Analog:** сам себя (17 тестов, well-structured).

**Setup pattern** (lines 48-61):
```swift
final class SberAuthServiceTests: XCTestCase {
    private var mockHTTP: MockHTTPClient!
    private var sut: SberAuthService!

    private let testCredentials: (clientId: String, secret: String) = ("test-id", "test-secret")

    override func setUp() {
        super.setUp()
        mockHTTP = MockHTTPClient()
        sut = SberAuthService(
            credentialProvider: { [testCredentials] in testCredentials },
            httpClient: mockHTTP
        )
    }
}
```

**makeValidTokenResponse helper** (lines 6-22) — создаёт `(Data, URLResponse)` с валидным OAuth payload. Если расширяем — взять этот же шаблон:
```swift
private func makeValidTokenResponse(
    token: String = "test-token",
    expiresInSeconds: TimeInterval = 1800
) -> (Data, URLResponse) {
    let expiresAtMs = (Date().timeIntervalSince1970 + expiresInSeconds) * 1000.0
    let json = """
    {"access_token": "\(token)", "expires_at": \(Int64(expiresAtMs))}
    """
    let data = Data(json.utf8)
    let response = HTTPURLResponse(
        url: URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!,
        statusCode: 200, httpVersion: nil, headerFields: nil
    )!
    return (data, response as URLResponse)
}
```

**DelayMockHTTPClient pattern** для coalescing-тестов (lines 26-44) — wraps MockHTTPClient + `await Task.sleep`. Используется в `test_concurrent_calls_coalesce`. Если расширяем coalescing-coverage — этот паттерн готов.

**URLError preservation pattern** (lines 86-96, 98-108) — тесты что `.networkError(urlError:description:)` сохраняет `URLError.code`:
```swift
func test_getAccessToken_networkError_preserves_urlError_notConnected() async {
    mockHTTP.error = URLError(.notConnectedToInternet)
    do {
        _ = try await sut.getAccessToken()
        XCTFail("Ожидалась ошибка")
    } catch let AuthError.networkError(urlErr, _) {
        XCTAssertEqual(urlErr?.code, .notConnectedToInternet)
    } catch {
        XCTFail("Ожидался AuthError.networkError, получен \(error)")
    }
}
```

**Coverage gap candidates:**
- Concurrent refresh при истёкшем токене (race с coalescing) — есть `test_expiredToken_triggersNewFetch`, но не в concurrent варианте
- `expires_at` в прошлом или 0 → ожидаемое поведение?
- HTTP 200 но пустой `access_token` → `.tokenParsingFailed`?

---

### `GovorunTests/CredentialStoreTests.swift` (test, CRUD via MockCredentialStore)

**Analog:** сам себя (9 тестов).

**Mock store API** — `MockCredentialStore` уже есть в `Govorun/Storage/CredentialStore.swift` lines 112-139 — содержит `saveCalls`, `saveError`, `deleteError` injection. **Не делать новый mock** — расширять флаги в существующем если потребуется.

**Test pattern** (lines 14-51) — простой CRUD + error injection:
```swift
func test_save_storesCredentials() throws {
    try store.save(clientId: "test-id", clientSecret: "test-secret")
    let creds = store.get()
    XCTAssertEqual(creds?.clientId, "test-id")
    XCTAssertEqual(creds?.secret, "test-secret")
}

func test_save_withError_throws() {
    store.saveError = CredentialStoreError.saveFailed(-25299)
    XCTAssertThrowsError(try store.save(clientId: "id", clientSecret: "secret")) { error in
        XCTAssertEqual(error as? CredentialStoreError, .saveFailed(-25299))
    }
}
```

**Coverage gap candidates:**
- Real `CredentialStore` (Keychain): нет интеграционного теста с `kSecAttrService` — это OK для unit, но проверить хватает ли purely-mock покрытия для D-07 audit confidence
- `delete` после `delete` → `errSecItemNotFound` (line 104) treated as success — проверить тестом
- Unicode в clientId/secret (emoji, кириллица)
- Very long strings (>4KB Keychain limit)

---

### `GovorunTests/SberTrustPolicyTests.swift` (test, bundle-resource I/O)

**Analog:** сам себя (15 тестов).

**Bundle-resource pattern** (lines 7-21):
```swift
func test_parsePEMCertificates_validPEM_returnsCertificates() {
    let pemPath = Bundle(for: type(of: self)).path(forResource: "SberRootCA", ofType: "pem")
        ?? Bundle.main.path(forResource: "SberRootCA", ofType: "pem")

    guard let path = pemPath,
          let data = FileManager.default.contents(atPath: path),
          let pemString = String(data: data, encoding: .utf8)
    else {
        XCTFail("SberRootCA.pem не найден в бандле")
        return
    }
    let certs = SberTrustPolicy.parsePEMCertificates(pemString)
    XCTAssertEqual(certs.count, 2)
}
```

**Temp directory pattern для bad-bundle инициализации** (lines 100-112):
```swift
func test_init_invalidPEM_throwsCertificateParsingFailed() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let pemFile = tmpDir.appendingPathComponent("SberRootCA.pem")
    try "NOT A CERTIFICATE".write(to: pemFile, atomically: true, encoding: .utf8)

    let bundle = Bundle(path: tmpDir.path)!
    XCTAssertThrowsError(try SberTrustPolicy(bundle: bundle)) { error in
        XCTAssertEqual(error as? TrustPolicyError, .certificateParsingFailed)
    }
}
```

**Coverage gap candidates:**
- Domain matching на edge cases: пустая строка, только точка, port в host (`api.sber.ru:443`), IPv6
- `urlSession.configuration` имеет правильный `URLSessionDelegate` (TrustingDelegate)
- Что происходит при HTTPS-запросе на не-Sber домен через `urlSession` — fallback на system CA

---

### `GovorunTests/AppStateCloudShimTests.swift` (test, @MainActor + DI)

**Analog:** сам себя (4 теста — самый малый, **наиболее вероятный кандидат на расширение** per CONTEXT.md).

**@MainActor test class pattern** (lines 4-5):
```swift
@MainActor
final class AppStateCloudShimTests: XCTestCase {
```

**Heavy AppState builder pattern** (lines 8-44) — сложный helper потому что `AppState` имеет много deps. Все mocks (`MockEventMonitoring`, `MockAudioRecording`, `MockSTTClient`, `MockLLMClient`, `MockAccessibility`, `MockClipboard`) уже существуют в проекте:
```swift
private func makeAppState(
    credentialStore: CredentialStoring,
    authService: AuthService? = nil
) -> (AppState, SettingsStore) {
    let suiteName = "com.govorun.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = SettingsStore(defaults: defaults)

    let appState = AppState(
        activationKeyMonitor: ActivationKeyMonitor(...),
        sessionManager: SessionManager(),
        pipelineEngine: PipelineEngine(...),
        textInserter: TextInserterEngine(...),
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
```

**UUID-suffixed UserDefaults suite pattern** — критично для test isolation (lines 13-14):
```swift
let suiteName = "com.govorun.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
```

**Result<Void, AuthError> pattern** для probe-tests (lines 79-93, 95-109):
```swift
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
```

**Coverage gap candidates (high priority — это самая узкая сейчас coverage в Phase 16):**
- `saveCloudCredentials` когда store.save кидает (передать `store.saveError = .saveFailed(-25299)`) — проверить что `cloudAvailable` НЕ становится `true`
- `deleteCloudCredentials` когда store.delete кидает — `cloudAvailable` поведение
- `probeCloudConnection` маппинг `URLError` → `AuthError.networkError(urlError:description:)` — branch lines 393-398 в AppState.swift сейчас не покрыт, нужен тест с `mockAuth.tokenError = URLError(.timedOut)` (не AuthError напрямую)
- `probeCloudConnection` без credentials в store — `MockAuthService` всё равно вернёт токен, но реальный поведение (`SberAuthService` с `credentialProvider` = `{ store.get() }` → `nil` → `AuthError.credentialsNotFound`) проверить через factory

---

### `GovorunTests/CloudSettingsErrorMessageTests.swift` (test, pure transform)

**Analog:** сам себя.

**Simple pure-function test pattern** (lines 7-13):
```swift
func test_credentialsNotFound() {
    XCTAssertEqual(
        cloudErrorMessage(for: AuthError.credentialsNotFound),
        "Введите ключи API. Без них Cloud недоступен."
    )
}
```

**Multiple status-code matrix pattern** (lines 31-35):
```swift
func test_invalidResponse_5xx() {
    let expected = "Ошибка на стороне Сбера. Попробуйте позже."
    XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 500)), expected)
    XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 503)), expected)
    XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 599)), expected)
}
```

**Non-AuthError fallback pattern** (lines 94-100) — критично для proof что generic Error не падает:
```swift
func test_nonAuthError_fallback() {
    struct OtherError: Error {}
    XCTAssertEqual(
        cloudErrorMessage(for: OtherError()),
        "Сбой Cloud. Попробуйте позже."
    )
}
```

**Coverage gap candidates:**
- `LLMError` → `cloudErrorMessage` mapping если функция принимает любой Error (проверить что она handles LLMError.timeout, .rateLimited, .serverError, .parsingFailed)
- `URLError(.cancelled)` через AuthError.networkError — должно ли быть отдельное сообщение от .timedOut?

---

### `scripts/benchmark-full-pipeline-helper.swift` (helper-binary, JSON line protocol)

**Analog:** сам себя — структура корректна, помечен «сломан» в CONTEXT, но при чтении видно что **код актуален и компилируется** против текущего `NormalizationPipeline.preflight/postflight` API. Поломка может быть в:
1. Несоответствии HELPER_SWIFT_SOURCES в `benchmark-llm-normalization.py:19-29` (если файлы переименованы)
2. Сигнатурах `NormalizationPipeline.preflight/postflight` — нужно сверить

**Verify-then-fix план:**
```bash
# 1. Попробовать скомпилировать как требует benchmark-llm-normalization.py:284-291:
xcrun swiftc -enable-bare-slash-regex \
  Govorun/Models/LLMOutputContract.swift \
  Govorun/Models/SnippetContext.swift \
  Govorun/Models/SnippetPlaceholder.swift \
  Govorun/Models/SuperTextStyle.swift \
  Govorun/Core/NumberNormalizer.swift \
  Govorun/Core/ListFormatter.swift \
  Govorun/Core/NormalizationGate.swift \
  Govorun/Core/NormalizationPipeline.swift \
  scripts/benchmark-full-pipeline-helper.swift \
  -o build/benchmark-full-pipeline-helper
# 2. Прочитать ошибки — это даст точный gap
```

**JSON line protocol pattern** (lines 41-67) — если переписывать на Python, шаблон такой:
```swift
@main
struct BenchmarkFullPipelineHelper {
    static func main() {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        while let line = readLine() {
            let response: Response
            do {
                let data = Data(line.utf8)
                let request = try decoder.decode(Request.self, from: data)
                response = try handle(request)
            } catch {
                response = .error(String(describing: error))
            }

            do {
                let data = try encoder.encode(response)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0a]))
            } catch {
                let fallback = #"{"ok":false,"error":"encoding_failed"}"#
                FileHandle.standardOutput.write(Data(fallback.utf8))
                FileHandle.standardOutput.write(Data([0x0a]))
            }
        }
    }
}
```

**Op dispatch pattern** (lines 70-156): switch on `request.op` for `prompt` / `preflight` / `postflight` / `failed-postflight`. Если добавляются новые ops (например `cloud-prompt` для cloud-mode bench) — расширять этот switch.

---

### `scripts/benchmark-llm-normalization.py` (benchmark, streaming HTTP + extend for cloud)

**Analog:** сам себя — extend существующий script.

**CLI args pattern** (lines 66-162) — добавить cloud-mode флаги по такому же шаблону:
```python
parser.add_argument(
    "--mode",
    choices=["local", "cloud"],
    default="local",
    help="local = llama-server endpoint, cloud = Sber GigaChat API.",
)
parser.add_argument(
    "--cloud-credentials",
    help="Path to .env.bench with GIGACHAT_CLIENT_ID and GIGACHAT_SECRET.",
)
parser.add_argument(
    "--cloud-model",
    default="GigaChat-2-Max",
    help="Cloud model identifier.",
)
```

**Local request_completion pattern** (lines 421-501) — образец для нового `request_completion_cloud`:
```python
def request_completion(
    *, base_url: str, model: str, user_text: str,
    system_prompt: str | None, timeout: float,
    max_tokens: int, temperature: float,
    stop: list[str] | None = None,
) -> tuple[str, float | None, float]:
    payload = {
        "model": model,
        "stream": True,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [],
    }
    # ... build request, stream SSE, collect deltas, return (text, first_token_ms, total_ms)
```

**Cloud request pattern** (новый, по образцу `request_completion`):
- Шаги: (1) OAuth POST к `https://ngw.devices.sberbank.ru:9443/api/v2/oauth` → получить bearer token, кэшировать пер-запуск; (2) если есть audio-data — POST multipart к `https://gigachat.devices.sberbank.ru/api/v1/files`; (3) POST JSON к `https://gigachat.devices.sberbank.ru/api/v1/chat/completions` с `Bearer <token>` header, `attachments: [file_id]` если был upload.
- Stream нет — Sber API в текущей spec не поддерживает SSE для chat/completions с attachments → `first_token_latency_ms = None`, mark как `total_latency_ms` only.
- Использовать `urllib.request` + `ssl.create_default_context()`. Для SberRootCA — pin cert через `ssl.load_verify_locations(cafile=...)` (Sber root cert location: `Govorun/Resources/SberRootCA.pem`).

**Cost estimation pattern** (нет в текущем скрипте — надо добавить per CONTEXT.md "если > 50K токенов — surface Sanya"):
```python
def estimate_token_cost(dataset: list[dict], avg_input_tokens: int = 50, avg_output_tokens: int = 30) -> int:
    return len(dataset) * (avg_input_tokens + avg_output_tokens)

# В main(), перед циклом запросов:
if args.mode == "cloud":
    estimated = estimate_token_cost(dataset)
    if estimated > 50_000:
        print(f"WARNING: estimated {estimated} tokens. Continue? [y/N]", file=sys.stderr)
        if input().strip().lower() != "y":
            return 1
```

**Quality summary pattern** (lines 545-694) — НЕ переделывать, использовать как есть. `summarize()` работает для любого режима (local/cloud) — расчёт `period_tolerant_pct` и `exact_match_pct` model-agnostic.

**Output pattern** (lines 897-908): per-sample row пишется в JSONL, summary — в JSON. Добавить в каждую row поле `"mode": "local" | "cloud"` и в summary тоже.

---

### `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md` (doc)

**Analog:** скорее всего нет прямого образца. Структура (предложение):
```markdown
# Phase 16: Benchmark Results — Cloud vs Local Quality

**Date:** 2026-04-XX
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples)
**Models:**
- Local: `GigaChat 3.1 10B-A1.8B Q4_K_M` (llama-server)
- Cloud: `GigaChat-2-Max` (Sber API)

## Methodology
- ... (deterministic temp, fixed seed, ground-truth in `expected` field)
- ... (number of cloud tokens spent: $X)

## Headline Metrics

| Metric | Local | Cloud | Delta |
|--------|-------|-------|-------|
| period-tolerant match | XX.X% | YY.Y% | +Z.Z pp |
| exact match | XX.X% | YY.Y% | +Z.Z pp |
| completed | XX.X% | YY.Y% | +Z.Z pp |

## Per-bucket breakdown
... (use existing summary["buckets"] shape from benchmark-llm-normalization.py)

## Failures
... (list of differences with expected/local/cloud columns)

## Decision input для Sanya
- Cloud-vs-local: ...
- Phase 17 rollout recommendation: ...

## Reproduction
\`\`\`bash
python3 scripts/benchmark-llm-normalization.py --mode local --output build/local.jsonl --summary build/local-summary.json
python3 scripts/benchmark-llm-normalization.py --mode cloud --cloud-credentials .env.bench --output build/cloud.jsonl --summary build/cloud-summary.json
\`\`\`
```

---

## Shared Patterns

### Mock injection через protocols (CONVENTIONS.md §Testing)
**Source:** `Govorun/Services/HTTPClient.swift` lines 5-7, `Govorun/Services/SberAuthService.swift` lines 162-180, `Govorun/Storage/CredentialStore.swift` lines 110-139, `Govorun/Services/SberTrustPolicy.swift` lines 125-133.
**Apply to:** все cloud-tests.
**Принцип:**
- Каждый сервис ставит `MockXxx` рядом с production-классом в **том же файле**, через `// MARK: - Мок`. НЕ создавать отдельные `Mocks/` модули.
- Mock оперирует через injectable публичные `var result/error/tokenResult/tokenError`, фиксирует вызовы через `private(set) var requests/saveCalls/normalizeCalls`.
- Все mocks `final class ... @unchecked Sendable` + `NSLock` (для concurrency-safe).

### Test naming + MARK structure
**Source:** все test-файлы — единый стиль.
**Apply to:** все новые тесты в Phase 16.
**Шаблон:**
```swift
final class XxxTests: XCTestCase {
    // MARK: - <Group label> (или Feature ID для cloud-tests)
    func test_<methodUnderTest>_<scenario>() async throws { ... }

    // MARK: - <Next group>
    func test_<methodUnderTest>_<scenario2>() async throws { ... }
}
```
- Group MARK секции группируют по: feature ID (CLOUD-01, D-07), либо happy/error/edge-case, либо по методу под тестом
- Имя теста: `test_<method>_<scenario>` — без camelCase для scenario, snake-style ОК (`test_getAccessToken_credentialsNotFound`).
- Russian comments OK (e.g. `XCTFail("Ожидался AuthError.networkError, получен \(error)")`).

### Equatable assertion для типизированных ошибок
**Source:** `SberAuthServiceTests.swift` lines 230-252, `CredentialStoreTests.swift` lines 73-77, `CloudLLMClientTests.swift` lines 596-614.
**Apply to:** любые тесты с typed errors.
**Шаблон:**
```swift
XCTAssertEqual(error as? AuthError, .credentialsNotFound)
// ИЛИ
guard case .networkError = error else { XCTFail("..."); return }
// ИЛИ для exhaustive equality:
XCTAssertEqual(error as? LLMError, .serverError(statusCode: 500))
```

### UUID-suffixed UserDefaults suite (test isolation)
**Source:** `AppStateCloudShimTests.swift` line 13.
**Apply to:** любой тест который инстанциирует `SettingsStore`.
```swift
let suiteName = "com.govorun.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
```

### NormalizationHints test factory
**Source:** `CloudLLMClientTests.swift` lines 33-37.
**Apply to:** любой тест который зовёт `LLMClient.normalize` или `CloudLLMClient.processAudio`.
```swift
private let testDate = Date(timeIntervalSince1970: 1_711_633_600)
private func makeHints() -> NormalizationHints {
    NormalizationHints(currentDate: testDate)
}
```

### Retry-test config: всегда задавать малый `retryDelay`
**Source:** `CloudLLMClientTests.swift` lines 276, 304.
**Apply to:** любой retry-test чтобы не тормозить test suite.
```swift
let client = CloudLLMClient(
    authService: mockAuth, httpClient: mockHTTP,
    configuration: CloudLLMConfiguration(retryDelay: 0.01)
)
```

### Multipart body decoding: `.isoLatin1` not `.utf8`
**Source:** `CloudLLMClientTests.swift` lines 130-131 (с комментарием).
**Apply to:** любой тест который проверяет multipart-body с binary-данными (WAV, image).
```swift
// isoLatin1 всегда декодирует любые байты 1:1, не теряя ASCII-delimiters
// из multipart (в отличие от .utf8, который вернёт nil на binary WAV-header).
let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.env.bench` | config / secrets | n/a | Нет существующего паттерна для bench-credentials. Простой `KEY=value` shell-формат, source через `set -a; source .env.bench; set +a` или Python `python-dotenv`. **Должен быть в `.gitignore`** (per CONTEXT.md). |
| `16-BENCHMARK-RESULTS.md` | doc | n/a | Папка `.planning/phases/16-tests/` пустая (только CONTEXT.md). Структуру предложил выше — planner финализирует. |

---

## Audit-First Recommendations (для planner)

CONTEXT.md явно говорит: **«Audit-first. Не добавлять тесты вслепую»**. Перед написанием новых тестов выполнить:

1. **Запустить `xcodebuild test` и собрать current coverage** для cloud-сервисов (если xcov / xcrun llvm-cov настроены — использовать; если нет — manual review против списка ниже).
2. **Coverage gap matrix** (priority order):

| Service | Current tests | Most likely gaps (per анализ кода) |
|---------|---------------|------------------------------------|
| **AppStateCloudShim** | 4 — самая узкая | save/delete error branches, probe URLError mapping (lines 393-398 AppState.swift), credentials-removed-mid-probe race |
| **CloudLLMClient** | 24 — выглядит достаточно | URLError(.timedOut) → LLMError.timeout mapping, empty `choices` parsing, очень большой WAV (>10MB multipart), CancellationError mid-retry |
| **CredentialStore** | 9 — простой CRUD | Real Keychain integration (опционально, не unit), unicode/long values, double-delete |
| **SberAuthService** | 17 — well-covered | Concurrent refresh при истечённом токене, `expires_at` в прошлом, empty `access_token` |
| **SberTrustPolicy** | 15 — comprehensive | Trust delegate behaviour (тестируется только `parsePEMCertificates`+ domain matching, не реальный `URLAuthenticationChallenge` обработчик; это OK так как требует network), domain matching edge cases |
| **CloudSettingsErrorMessage** | 13 — comprehensive | LLMError mapping (если функция принимает Error, а не AuthError) |

3. **Если все gaps уже покрыты** → audit-results записать как часть PLAN, перейти к benchmark.
4. **Если найдены gaps** → добавить unit-тесты в существующие файлы (НЕ создавать новые файлы — расширять существующие, чтобы держать связку test-file ↔ service-file).

---

## Metadata

**Analog search scope:** `GovorunTests/`, `Govorun/Services/`, `Govorun/Storage/`, `Govorun/App/`, `scripts/`, `benchmarks/`.
**Files scanned:** 50 test files, 6 cloud-service files (`CloudLLMClient.swift`, `SberAuthService.swift`, `CredentialStore.swift`, `SberTrustPolicy.swift`, `HTTPClient.swift`, `AppState.swift`), 2 benchmark scripts (`benchmark-llm-normalization.py`, `benchmark-full-pipeline-helper.swift`).
**Pattern extraction date:** 2026-04-23.
