# Phase 16: Tests — Research

**Researched:** 2026-04-23
**Domain:** Test coverage audit + cloud-vs-local quality benchmark
**Confidence:** HIGH (verified — все источники прочитаны, helper откомпилирован, тесты подсчитаны)

## Summary

Цель фазы — закрыть тестовый долг v2.0 перед Polish & Rollout: (1) аудит покрытия cloud-стека и точечное закрытие найденных дыр, (2) запуск cloud-vs-local benchmark на существующем eval seed.

**Ключевая находка по покрытию:** существующие 1299 тестов покрывают cloud-стек гораздо лучше, чем казалось. Аудит выявил **только две реальные дыры**: (1) `CredentialStore` (Keychain implementation) полностью НЕ покрыт — `CredentialStoreTests.swift` тестирует только `MockCredentialStore`; (2) AppState methods `saveCloudCredentials/deleteCloudCredentials/probeCloudConnection` имеют по 1 тесту happy/sad path, но нет тестов на проброс `CredentialStoreError`. Всё остальное (CloudLLMClient, SberAuthService, SberTrustPolicy, NetworkMonitor, PipelineEngine cloud path, ProductMode, CloudErrorCopy, AppState cloud wiring через IntegrationTests) покрыто адекватно.

**Ключевая находка по benchmark:** `benchmark-full-pipeline-helper.swift` **НЕ сломан** — компилируется чисто текущим `xcrun swiftc` против актуальных Swift sources, smoke-test `op:prompt` возвращает корректный production prompt. Helper уже содержит SuperTextStyle support; legacy `--text-mode` остался deprecated alias, но рабочий. Контекст-документ устарел в этом утверждении.

**Primary recommendation:** Phase 16 разбивается на 3 плана: **Plan 1** — закрыть две найденные dyrы (CredentialStore Keychain integration tests + AppState shim error-path tests, ≈12 новых тестов); **Plan 2** — расширить `benchmark-llm-normalization.py` с `--mode cloud|local` + создать `BENCHMARK-RESULTS.md` template; **Plan 3** — выполнить cloud vs local прогон на 36 seed samples и задокументировать результаты.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Test coverage policy:**
- **Audit-first:** не добавлять тесты вслепую. Сначала анализ существующих 69 cloud-тестов, потом таргетированное закрытие gaps
- **Mock-only:** unit-тесты не делают сетевых вызовов. `MockHTTPClient`, `MockAuthService`, `MockTrustPolicy` уже есть
- **Coverage targets per service** (минимум):
  - SberAuthService — happy path, token expiry, refresh, retry, parse errors, credentialsNotFound (✓ 17 тестов — достаточно)
  - CloudLLMClient — upload (WAV), chat, attachments, retry, cancellation, error mapping (✓ 24 теста — достаточно)
  - CredentialStore — save/get/delete, Keychain errors (✓ 9 тестов — **проверить что edge cases закрыты** ← AUDIT NOTE: реализация Keychain не покрыта вообще, см. Coverage Gap Analysis)
  - SberTrustPolicy — match `*.sberbank.ru`, fallback на system CA (✓ 15 тестов — достаточно)
  - AppStateCloudShim — saveCloudCredentials, deleteCloudCredentials, probeCloudConnection (✓ 4 теста — может быть мало, проверить)
  - CloudSettingsErrorMessage / cloudErrorMessage(for:) — все AuthError/LLMError кейсы → user copy

**Benchmark methodology:**
- **Dataset:** существующий eval seed (`benchmarks/llm-normalization-seed.jsonl`, 36 samples). Если seed устарел или мал — **остановиться и спросить Sanya**, не выдумывать
- **Models compared:** `GigaChat-2-Max` (cloud) vs `GigaChat 3.1 10B-A1.8B Q4_K_M` (local llama-server)
- **Metric:** zero-edit rate (% выходных строк, не требующих ручной правки) — основной. Token diff / character-level edit distance — secondary
- **Scoring:** automatic via diff против ground-truth в seed. Если ground-truth недостаточен или субъективен — flag для human eval (out of scope)
- **Threshold:** не зашивать «cloud должен быть не хуже local на X%» — записать results, дать Sanya решить про Phase 17 rollout

**Benchmark script repair:**
- `benchmark-full-pipeline-helper.swift` — оценить: чинить (если осталось < 1 час работы) или заменить новой Python-точкой входа (если refactor занимает больше). Решение в plan-task — surface options. **AUDIT NOTE: helper уже работает, см. Swift Helper Repair Analysis**
- `benchmark-llm-normalization.py` — основной runner, должен поддержать `--mode cloud|local`. Cloud путь делает реальные вызовы к Sber API → требует sourced credentials (`.env.bench` или прямые args, **не коммитить ключи**)

**Безопасность тестов:**
- Bench-credentials отдельно от prod (developers.sber.ru → создать второй клиент или использовать тот же — Sanya решает)
- `.env.bench` в `.gitignore`
- Benchmark-результаты можно коммитить (агрегаты), сами audio + transcripts — нет (PII)

### Claude's Discretion

- Точные имена test-файлов и функций
- Структура `BENCHMARK-RESULTS.md`
- Конкретный shape новых mock-helpers если понадобятся

### Deferred Ideas (OUT OF SCOPE)

- XCUITest для CloudSettingsDisclosure flows (UAT-J VoiceOver) — pre-release pass
- Latency p50/p90/p95 cloud vs local — Phase 17 (CLOUD-06)
- Live integration tests с реальным Sber sandbox — too costly, не нужно

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | Unit-тесты для SberAuthService, CloudPipelineClient (=CloudLLMClient), CredentialStore через моки | Coverage Gap Analysis ниже выявил 2 дыры; план должен закрыть **CredentialStore Keychain integration** + **AppStateCloudShim error-path tests** |
| TEST-02 | Benchmark качества cloud vs локальная модель на существующем seed | Benchmark Script Audit + Validation Architecture ниже описывают расширение `benchmark-llm-normalization.py` с `--mode cloud` и шаблон `BENCHMARK-RESULTS.md` |

## Project Constraints (from CLAUDE.md)

| Directive | Source | Enforcement in Phase 16 |
|-----------|--------|------------------------|
| TDD red→green→refactor | §Conventions | Любые новые тесты пишутся first; реализация (если нужна) — после теста |
| Моки через протоколы, никогда реальный Python worker или модели | §Тесты | Cloud HTTP моки уже есть. Plan 1 НЕ должен ходить в Sber API из unit-тестов |
| Нет force unwrap (`!`) в production коде | §Error Handling | Phase 15 H-01 уже закрыл — но новый test code может использовать `XCTUnwrap` (это допустимо) |
| async/await, не completion handlers | §Async/Concurrency | Все новые async tests — `async throws` |
| Комментарии минимальные, на русском | §Language and Comments | Test comments на русском, минимально |
| Коммиты на русском, нет Co-Authored-By | §Commit Conventions | Применяется ко всем commits Phase 16 |
| `xcodebuild test -scheme Govorun ...` — единственная команда | §Команды | Используется в Validation Architecture как полный suite run |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Test framework execution | Test target (GovorunTests) | — | XCTest, единый xctestplan |
| Unit test mocking | Test target | Services/Storage/Core (источники протоколов) | Mocks конформят к production protocols (`AuthService`, `HTTPClient`, `CredentialStoring`, `CloudAudioProcessing`, `NetworkAvailabilityProviding`) |
| Real Keychain integration tests | Test target | Storage/CredentialStore.swift | Тесты используют реальный `CredentialStore`, но с unique service-scoped accounts чтобы не загрязнять system Keychain |
| Benchmark runner (cloud + local modes) | scripts/benchmark-llm-normalization.py | scripts/benchmark-full-pipeline-helper.swift, Sber GigaChat API | Python orchestrates, Swift helper генерирует production prompts, Sber API возвращает реальные completions |
| Benchmark dataset (ground truth) | benchmarks/llm-normalization-seed.jsonl | — | Существующий seed (36 samples), используется без модификаций |
| Benchmark results documentation | .planning/phases/16-tests/16-BENCHMARK-RESULTS.md | benchmarks/reports/*.md (исторические референсы) | Markdown table + анализ, **БЕЗ** raw audio/transcripts (PII) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| XCTest | bundled with Xcode 15.4 | Unit/integration tests | Apple-stock, единственный framework в проекте (1299 tests) [VERIFIED: Govorun.xctestplan, ls GovorunTests/] |
| Swift stdlib | 5.10 | async/await, Sendable, Result | Существующая project convention [VERIFIED: project.yml SWIFT_VERSION] |
| Foundation/Security | macOS 14.0+ | Keychain via SecItem* APIs | CredentialStore уже использует [VERIFIED: Govorun/Storage/CredentialStore.swift] |
| Python 3.13 | embedded или system | benchmark runner | Существующий скрипт работает [VERIFIED: scripts/benchmark-llm-normalization.py shebang] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `urllib.request` (Python stdlib) | — | HTTP calls к Sber API в benchmark | Уже используется в `benchmark-llm-normalization.py:request_completion()` для llama-server; для Sber нужны другие заголовки (Bearer token + RqUID) |
| `os.environ` (Python stdlib) | — | Чтение `.env.bench` для bench credentials | Стандартный паттерн для секретов вне git |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Real CredentialStore in tests | Только MockCredentialStore | Не покрываем реальные Keychain edge cases (errSecDuplicateItem, errSecItemNotFound, biometric prompts на signed builds). Prod-Keychain тесты с unique service-suffix — стандартный паттерн (см. SettingsStoreTests UUID-suffixed suite name pattern в CLAUDE.md §Settings/UserDefaults) |
| Расширение benchmark-llm-normalization.py | Новый отдельный benchmark-cloud.py | Дублирование (dataset loading, summary/quality logic). Расширение существующего runner с `--mode {cloud,local}` flag — DRY и сохраняет shared output schema |
| `requests` library | `urllib.request` | Существующий скрипт уже на urllib — не добавлять third-party dep ради 1 endpoint |

**Installation:** Никаких новых зависимостей. Всё из stdlib + bundled XCTest.

**Version verification:** Зависимости только Apple/Python stdlib + project's existing test infrastructure (verified via `cat Govorun.xctestplan` и `ls GovorunTests/`). Никаких npm/pip пакетов добавлять не требуется.

## Coverage Gap Analysis

### Methodology

Cross-checked **public functions and branches** в каждом cloud-related Swift файле против существующих 1299 XCTest тестов. Использовал `grep -c "func test_"` для подсчёта и `grep -n` для поиска coverage по сущности.

### Per-File Audit

#### `Govorun/Services/CloudLLMClient.swift` — **ADEQUATE coverage (24 tests)**
[VERIFIED: GovorunTests/CloudLLMClientTests.swift]

| Public surface | Test coverage | Status |
|----------------|---------------|--------|
| `processAudio(audioData:superStyle:hints:)` | upload, completion, attachment, response extract, retry on 5xx, retry on 429, no retry on upload error, no retry on 4xx, cancellation, AuthError mapping (4 cases) | ✅ Full |
| `normalize(_:superStyle:hints:)` (LLMClient conformance) | text-only path, empty text early-return, baseURL guard | ✅ Full |
| `wrapPCMAsWAV(_:sampleRate:channels:bitsPerSample:)` static helper | покрыт через `test_processAudio_uploadsWAVFile` (проверяет RIFF/WAVE markers и embedded PCM bytes) | ✅ Indirect but adequate |
| `CloudLLMConfiguration` defaults + clamps negative timeout | `test_defaultConfiguration`, `test_configurationClampsNegativeTimeout` | ✅ Full |
| `LLMError.isRetryable` extension | 5 tests (rateLimited/serverError/timeout/networkError/parsingFailed) | ✅ Full |
| `function_call: "auto"` injection при attachments | НЕ ПОКРЫТО — нет assertion что body contains `function_call` | ⚠️ **Minor gap** (1 test) |
| `mapTransportError(_:)` — URLError → LLMError mapping | Частично через `test_processAudio_propagatesCancellation`, но `.cannotConnectToHost`/`.notConnectedToInternet` → `.networkError("GigaChat API недоступен")` НЕ ПОКРЫТО | ⚠️ **Minor gap** (1-2 tests) |

**Recommendation:** 1-2 точечных теста на `function_call` injection и URLError mapping. Не критично.

#### `Govorun/Services/SberAuthService.swift` — **ADEQUATE coverage (17 tests)**
[VERIFIED: GovorunTests/SberAuthServiceTests.swift]

| Public surface | Test coverage | Status |
|----------------|---------------|--------|
| `getAccessToken()` happy path | ✅ | Full |
| `credentialsNotFound` | ✅ | Full |
| `networkError` preserves URLError (notConnectedToInternet, timedOut) | ✅ 2 tests | Full |
| `invalidResponse(401)` | ✅ | Full |
| `tokenParsingFailed` | ✅ | Full |
| Token cache reuse | ✅ `test_cachedToken_returnedWithoutHTTPCall` | Full |
| Expired token triggers refetch | ✅ `test_expiredToken_triggersNewFetch` | Full |
| Concurrent calls coalesce | ✅ `test_concurrent_calls_coalesce` (3 async let) | Full |
| Request format (RqUID, Basic auth, body, POST, Content-Type) | ✅ 5 tests | Full |
| Custom tokenURL/scope | ✅ 2 tests | Full |
| `AuthError` Equatable semantics | ✅ `test_authError_equatable` | Full |
| `refreshMargin` (5 минут) — boundary test | НЕ ПОКРЫТО точечным тестом, но косвенно через `test_expiredToken_triggersNewFetch(expiresInSeconds: -10)` | ✅ Adequate |

**Recommendation:** Покрытие достаточно. Нет действий.

#### `Govorun/Storage/CredentialStore.swift` — **CRITICAL GAP** (0 tests against real implementation)
[VERIFIED: GovorunTests/CredentialStoreTests.swift uses **only** `MockCredentialStore`]

`CredentialStoreTests.swift` строка 5: `private var store: MockCredentialStore!` — все 9 тестов гоняют **только мок**, не реальный Keychain. Это значит:

| Public surface | MockCredentialStore tests | Real CredentialStore tests | Gap |
|----------------|---------------------------|----------------------------|-----|
| `save(clientId:clientSecret:)` | ✅ | ❌ | Реальный SecItemAdd path не проверяется |
| `get()` | ✅ | ❌ | Реальный SecItemCopyMatching path не проверяется |
| `delete()` | ✅ | ❌ | Реальный SecItemDelete path не проверяется |
| Upsert (delete-then-add via `save`) | ❌ — мок просто overwrites | ❌ | Регрессия `errSecDuplicateItem` не поймается |
| `errSecItemNotFound` tolerated by `delete()` | ❌ | ❌ | Логика guard `status == errSecItemNotFound` не проверяется |
| Concurrent save+get (NSLock) | ❌ | ❌ | Lock коректность не проверяется |
| `CredentialStoreError.saveFailed/deleteFailed` from real OSStatus | Только injection через `saveError`/`deleteError` | ❌ | Реальные OSStatus codes не воспроизводятся |

**Recommendation:** Это **главная coverage gap фазы.** Plan 1 должен добавить `CredentialStoreKeychainTests.swift` с реальным `CredentialStore` (не мок) и unique service identifier через UUID-suffix:

```swift
// Pattern из SettingsStoreTests (CLAUDE.md §Settings/UserDefaults)
private final class TestCredentialStore: CredentialStore {
    init() {
        // Override Keys.service на unique значение per test чтобы не пересекаться
    }
}
```

Однако `Keys.service` в `CredentialStore` — `private enum`. Для тестируемости либо:
- **(A)** добавить optional `serviceOverride: String? = nil` параметр в `init` (DI)
- **(B)** в test setUp/tearDown очищать known fixed service `com.govorun.app.credentials` через `SecItemDelete` всех accounts перед/после каждого теста

Опция (A) предпочтительнее — изоляция между тестами без shared state, не загрязняет prod Keychain. Surface обе опции в plan-task.

Целевое покрытие: ≈8-10 новых тестов (save → get round-trip, delete idempotency, upsert overwrites, save followed by save with new value, get on empty returns nil, errSecItemNotFound tolerated, concurrent access via DispatchQueue.concurrentPerform).

#### `Govorun/Services/SberTrustPolicy.swift` — **ADEQUATE coverage (15 tests)**
[VERIFIED: GovorunTests/SberTrustPolicyTests.swift]

| Public surface | Test coverage | Status |
|----------------|---------------|--------|
| `parsePEMCertificates(_:)` valid/empty/invalid base64/mixed | ✅ 4 tests | Full |
| `isSberDomain(_:)` exact match, subdomain, case-insensitive, false cases | ✅ 7 tests | Full |
| `init(bundle:)` valid/empty/invalidPEM | ✅ 3 tests | Full |
| `MockTrustPolicy` protocol conformance | ✅ 1 test | Full |
| `SberTrustDelegate.urlSession(_:didReceive:)` сам challenge handler | НЕ ПОКРЫТО — приватный класс, требует mock URLSession setup. Из protocol-боковой стороны покрыт через `MockTrustPolicy`. | ⚠️ Acceptable (private class, hard to test) |

**Recommendation:** Coverage достаточен. Не действовать.

#### `Govorun/App/AppState.swift` cloud shim — **MOSTLY adequate (4 dedicated + 7 integration tests)**
[VERIFIED: GovorunTests/AppStateCloudShimTests.swift + IntegrationTests.swift lines 643–846]

| Public surface | Test coverage | Status |
|----------------|---------------|--------|
| `saveCloudCredentials(clientId:clientSecret:)` happy path → `cloudAvailable=true` | ✅ AppStateCloudShimTests | Full |
| `deleteCloudCredentials()` → `cloudAvailable=false`, consent retained (D-07) | ✅ AppStateCloudShimTests | Full |
| `probeCloudConnection()` success | ✅ AppStateCloudShimTests | Full |
| `probeCloudConnection()` failure (AuthError.invalidResponse) | ✅ AppStateCloudShimTests | Full |
| `applyProductMode(.cloud)` wires CloudLLMClient | ✅ IntegrationTests | Full |
| `applyProductMode(.cloud)` credential gate blocks без credentials | ✅ IntegrationTests | Full |
| `applyProductMode(.cloud)` stops local llmRuntimeManager | ✅ IntegrationTests | Full |
| `applyProductMode(.standard/.superMode)` clears cloudClient | ✅ IntegrationTests 2 tests | Full |
| Guard audit (G1–G10): cloud не запускает local llama-server | ✅ IntegrationTests 7 tests | Full |
| `cloudAvailable` recompute on init | ✅ IntegrationTests 2 tests | Full |
| `saveCloudCredentials` пробрасывает `CredentialStoreError.saveFailed` | ❌ НЕ ПОКРЫТО | ⚠️ **Gap** |
| `deleteCloudCredentials` пробрасывает `CredentialStoreError.deleteFailed` | ❌ НЕ ПОКРЫТО | ⚠️ **Gap** |
| `probeCloudConnection()` non-AuthError → wraps in `.networkError` | ❌ НЕ ПОКРЫТО | ⚠️ **Gap** |

**Recommendation:** 3 точечных теста error propagation в shim:

```swift
func test_saveCloudCredentials_propagatesStoreError() throws {
    let store = MockCredentialStore()
    store.saveError = CredentialStoreError.saveFailed(-25299)
    let (appState, _) = makeAppState(credentialStore: store)
    XCTAssertThrowsError(try appState.saveCloudCredentials(clientId: "a", clientSecret: "b")) { ... }
    XCTAssertFalse(appState.cloudAvailable, "при ошибке save — cloudAvailable не флипается на true")
}
```

#### `Govorun/Views/CloudErrorCopy.swift` — **FULL coverage (10 tests)**
[VERIFIED: GovorunTests/CloudSettingsErrorMessageTests.swift]

| Branch | Test coverage |
|--------|---------------|
| `credentialsNotFound` | ✅ |
| `invalidResponse(401)`, `(429)`, `(500/503/599)`, `(other)` | ✅ 4 tests |
| `tokenParsingFailed` | ✅ |
| `networkError(notConnectedToInternet/networkConnectionLost)` | ✅ |
| `networkError(timedOut)` | ✅ |
| `networkError(cannotFindHost/nil URLError)` generic | ✅ |
| Non-AuthError fallback | ✅ |

**Recommendation:** Полностью покрыт. Нет действий.

#### `Govorun/Core/NetworkMonitor.swift` + `NetworkAvailabilityProviding` protocol — **ADEQUATE (6 tests)**
[VERIFIED: GovorunTests/NetworkAvailabilityTests.swift]

| Public surface | Test coverage | Status |
|----------------|---------------|--------|
| `NetworkMonitor` conforms to `NetworkAvailabilityProviding` (compile check) | ✅ | Full |
| `MockNetworkAvailability` implements protocol correctly | ✅ 3 tests | Full |
| `PipelineEngine` accepts `networkAvailability` via init + default nil | ✅ 2 compile-checks + 1 runtime | Full |
| `NetworkMonitor.isCurrentlyConnected` actual NWPathMonitor behavior | ❌ НЕ ПОКРЫТО — system-dependent (tests don't toggle Wi-Fi) | ⚠️ Acceptable (NWPathMonitor side-effects) |
| `PipelineEngine` cloud offline fallback (D-09 routes to local STT) | ✅ 3 tests в PipelineEngineTests (`test_cloud_mode_offline_routes_to_local_stt`, `test_cloud_mode_online_proceeds_normally`, `test_cloud_mode_without_network_provider_proceeds_online`) | Full |

**Recommendation:** Adequate. Не действовать.

#### `Govorun/Core/PipelineEngine.swift` cloud path — **STRONG coverage (17 tests)**
[VERIFIED: GovorunTests/PipelineEngineTests.swift lines 1505–1973]

Все 17 cloud-related тестов уже существуют:
- `test_cloud_mode_skips_stt`, `test_cloud_mode_calls_processAudio`
- `test_cloud_mode_empty_audio`, `test_cloud_mode_applies_post_processing`
- `test_cloud_mode_failure_returns_cloudFailed`, `test_cloud_mode_cancellation`
- `test_cloud_mode_rawTranscript_is_cloud_output`
- `test_cloud_mode_offline_routes_to_local_stt`, `test_cloud_mode_online_proceeds_normally`, `test_cloud_mode_without_network_provider_proceeds_online`
- `test_cloud_mode_applies_personal_dictionary_after_output`
- `test_cloud_mode_standalone_snippet_replaces_entire_text`, `test_cloud_mode_embedded_snippet_uses_cleanSubstitute`, `test_cloud_mode_embedded_snippet_passthrough_when_cloud_already_substituted`, `test_cloud_mode_no_snippet_match_passes_through`
- `test_cloud_mode_passes_snippet_dictionary_to_processAudio`
- `test_cloud_mode_list_formatter_applied_after_snippet`

**Recommendation:** Coverage отличный. Не действовать.

#### `Govorun/Storage/SettingsStore.swift` cloud consent — **ADEQUATE (4 tests)**
[VERIFIED: GovorunTests/SettingsStoreTests.swift lines 273-294]

`test_cloudConsentAcceptedAt_persists`, `test_clearCloudConsent_removesValue`, и persistence через перезапуск SettingsStore — полностью.

#### `Govorun/Models/ProductMode.swift` — **FULL coverage**
[VERIFIED: GovorunTests/ProductModeTests.swift — 15+ cloud-specific tests]

`test_cloud_rawValue`, `test_cloud_usesLLM`, `test_cloud_usesLocalLLM`, `test_cloud_isCloud`, `test_cloud_title`, `test_cloud_subtitle`, `test_codable_roundtrip_cloud`, `test_caseIterable_includes_cloud` — все ветви покрыты.

### Coverage Gap Summary

| Gap | Severity | Effort | Plan placement |
|-----|----------|--------|----------------|
| **CredentialStore Keychain implementation untested** (only mock tested) | **HIGH** — реальная Storage реализация без тестов = production risk | ≈8-10 tests, 1-2 ч (требует DI для service-name override OR cleanup setUp) | **Plan 1 — Coverage Closure** |
| AppStateCloudShim error propagation (saveError/deleteError/non-AuthError in probe) | MEDIUM | 3 tests, 30 мин | Plan 1 — Coverage Closure |
| CloudLLMClient `function_call: "auto"` body injection | LOW | 1 test, 10 мин | Plan 1 — Coverage Closure (optional) |
| CloudLLMClient `mapTransportError` URLError → LLMError mapping cases | LOW | 1-2 tests, 15 мин | Plan 1 — Coverage Closure (optional) |

**Total new tests in Plan 1: ≈12-15.** Roughly aligns with audit-first decision: «не насиловать тесты ради счёта».

## Benchmark Script Audit

### Current Shape (`scripts/benchmark-llm-normalization.py`)
[VERIFIED: full file read, 981 lines]

**Architecture:**
- CLI runner на pure Python 3 stdlib (`urllib.request`, `argparse`, `subprocess`)
- Modes: `--pipeline-mode {llm-only, full-pipeline}` — controlled via flag
- Dataset: `benchmarks/llm-normalization-seed.jsonl` (36 samples) [VERIFIED: `wc -l`]
- Endpoint: defaults `http://127.0.0.1:8080/v1` (local llama-server OpenAI-compatible)
- HTTP transport: streaming SSE через `urllib.request` с `stream: true` payload
- Output: per-sample JSONL + aggregated summary JSON (`build/llm-normalization-benchmark-summary.json`)

**Quality metrics already implemented (lines 545-694):**
- Total samples / completed / errors
- Exact match (output == expected)
- Period-tolerant match (output.rstrip('.') == expected.rstrip('.'))
- Per-bucket breakdowns (short/medium/long)
- Latency: p50/p95/max + first_token_latency
- RSS sampling (optional via `--server-pid`)
- Failure list with id, expected, got

**Key design choices to preserve:**
- `expected_full_pipeline` field в seed — для dual-axis ground truth (raw LLM vs full pipeline) [VERIFIED: head of seed shows `expected_full_pipeline` populated]
- `prompt_sha256` в summary — позволяет диффать прогоны на разных промптах
- `--warmup N` — первые N samples не считаются в metrics (cold start exclusion)
- Detailed FAILURES section в stdout output

**Existing reports (7 files в `benchmarks/reports/`):** показывают 80.6% exact match на full-pipeline mode normal style на M1/16GB [VERIFIED: 2026-04-04-full-pipeline-normal-postfix-m1-16gb.md].

### Where `--mode cloud` Plugs In

Текущий код имеет **одну точку HTTP-вызова**: `request_completion()` (lines 421-501). Он формирует OpenAI-compatible payload и парсит SSE chunks.

**Минимальные изменения для `--mode cloud`:**

1. **Новый CLI flag** (после `--pipeline-mode`):
   ```python
   parser.add_argument("--mode", choices=["local", "cloud"], default="local",
                       help="Backend: 'local' = OpenAI-compatible (llama-server), 'cloud' = Sber GigaChat")
   ```

2. **Cloud-specific config bundle** (новые args, опциональны при `--mode local`):
   ```python
   parser.add_argument("--cloud-base-url", default="https://gigachat.devices.sberbank.ru/api/v1")
   parser.add_argument("--cloud-model", default="GigaChat-2-Max")
   parser.add_argument("--cloud-credentials-env", default=".env.bench",
                       help="Path to .env file with SBER_CLIENT_ID and SBER_CLIENT_SECRET")
   parser.add_argument("--cloud-token-url",
                       default="https://ngw.devices.sberbank.ru:9443/api/v2/oauth")
   ```

3. **Новый helper `obtain_sber_token()`** (≈40 lines):
   - Читает `.env.bench` (parse `KEY=value` lines, комменты #)
   - POST к `--cloud-token-url` с Basic auth (clientId:secret base64) + form body `scope=GIGACHAT_API_PERS` + RqUID header
   - Парсит `{"access_token": ..., "expires_at": ms}`
   - Кеширует в module-level dict {token, expires_at} с refresh margin 5 минут
   - Использует Sber root CA — либо через `ssl.create_default_context(cafile=...)` указывая на `Govorun/Resources/SberRootCA.pem`, либо через certifi (если уже установлен) с warning что cert pinning не включён

4. **Бранч в `request_completion()`:** если `--mode cloud`, заменить `base_url` и `model` на cloud-аналоги, добавить `Authorization: Bearer {token}` header.

5. **Cloud-specific metric label в summary:** `mode: "cloud"` или `"local"`, чтобы reports можно было сравнивать.

**Effort estimate:** ≈80–100 lines кода, 1.5–2 часа работы. Чистое расширение, без breaking changes к существующим local prog runs.

**Cloud caveats для plan-task:**
- Cloud SSE: GigaChat поддерживает `stream: true`, но проверить — возможно chunk format отличается. Если не SSE — fallback на non-streaming JSON response (быстрая правка).
- WAV upload mode: для honest cloud benchmark нужно audio-in путь (`/files` upload + chat with attachments). Но **seed dataset — текстовые input**, не audio. Honest сравнение: либо (a) cloud тоже text-only вход → benchmark `normalize()` метода, не `processAudio()`; либо (b) пригенерить TTS-аудио из seed inputs (сильно расширяет scope, **не делать без явного approval Sanya**).
- **Recommendation:** сделать (a) — `--mode cloud` использует chat/completions с text input, тот же endpoint что local llama-server. Это симметричное сравнение «как LLM нормализует одинаковый текстовый input». Audio-in benchmarking отложить до когда есть TTS-датасет.

## Swift Helper Repair Analysis

### Status: NOT BROKEN [VERIFIED: compiled and ran successfully]

CONTEXT.md заявляет helper «сломан после удаления TextMode в v1.0», но это **неверно**. Проверка:

```bash
$ xcrun swiftc -enable-bare-slash-regex \
    Govorun/Models/LLMOutputContract.swift Govorun/Models/SnippetContext.swift \
    Govorun/Models/SnippetPlaceholder.swift Govorun/Models/SuperTextStyle.swift \
    Govorun/Core/NumberNormalizer.swift Govorun/Core/ListFormatter.swift \
    Govorun/Core/NormalizationGate.swift Govorun/Core/NormalizationPipeline.swift \
    scripts/benchmark-full-pipeline-helper.swift -o /tmp/test-helper
# Exit code 0, no output (clean compile)

$ echo '{"op":"prompt","superStyle":"normal","currentDate":"2026-04-23"}' | /tmp/test-helper
# Returns valid JSON with full production system prompt
```

Helper уже мигрирован на SuperTextStyle:
- `parseSuperStyle(_:)` — primary path берёт `request.superStyle` (raw value `"relaxed"|"normal"|"formal"`)
- `mapLegacyTextMode(_:)` — fallback на legacy `--text-mode` flag (deprecated, но рабочий)
- 4 ops: `prompt`, `preflight`, `postflight`, `failed-postflight` — все работают

[VERIFIED: грепом подтверждено НЕТ ссылок на удалённый `TextMode` enum, только legacy string mapping в `mapLegacyTextMode`]

### Action

**Никакой репарации не требуется.** Plan-task для Phase 16 НЕ должен включать «починить helper». Surface это как finding в plan и предложить:
- Option A: оставить как есть (рабочий + legacy compatibility)
- Option B: удалить deprecated `--text-mode` / `mapLegacyTextMode()` cleanup в отдельном маленьком commit (опционально, не блокирует benchmark)

Recommendation: A. Не трогать рабочий код перед benchmark прогоном — снижаем риски.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OpenAI-compatible HTTP client в benchmark | Новый Swift/Python wrapper | Existing `request_completion()` в benchmark-llm-normalization.py | Уже handles SSE streaming, errors, latency timing; нужно только параметризовать base_url/model/headers |
| Sber OAuth token refresh в benchmark | Свой SberAuthService на Python | Простой `obtain_sber_token()` helper с in-process cache | Production SberAuthService — Swift actor; для standalone Python benchmark — overkill. Простой dict-cache на module level достаточно |
| Test framework для cloud | Новый XCTest helper class | Existing `MockHTTPClient`, `MockAuthService`, `MockCredentialStore`, `MockTrustPolicy`, `MockCloudAudioClient`, `MockNetworkAvailability` | Все mocks уже есть в проекте, Phase 16 НЕ должна создавать новые mock infrastructure |
| Benchmark dataset | Расширять или менять seed | Существующий `benchmarks/llm-normalization-seed.jsonl` (36 samples) | CONTEXT.md locked decision — «если seed устарел, спросить Sanya». Используем как есть |
| Quality scoring | Перцептуальный/LLM-as-judge eval | Existing `exact_match`, `period_tolerant_match` в `summarize()` | Объективный метод уже есть, добавлять human-in-loop вне scope |

**Key insight:** Phase 16 — это **аудит+benchmark**, не **рефакторинг тестового фреймворка**. Все необходимые mocks и helpers уже существуют от phases 10-15. План должен использовать их, не создавать новые.

## Common Pitfalls

### Pitfall 1: Реальный CredentialStore тест засоряет system Keychain

**What goes wrong:** Тест записывает `service=com.govorun.app.credentials, account=gigachat.clientId, value=test-id` в Keychain. После теста запись остаётся; при запуске prod app `CredentialStore.get()` возвращает test-id вместо реальных credentials.
**Why it happens:** Keychain — global per-user store, не sandboxed по test bundle. Без cleanup в tearDown тестовые данные «протекают».
**How to avoid:**
- Option A: добавить `init(serviceOverride: String? = nil)` в `CredentialStore`, тесты используют `service: "com.govorun.tests.\(UUID().uuidString)"`
- Option B: в setUp/tearDown очищать service `com.govorun.app.credentials` через `SecItemDelete`
- **Recommend Option A** — изоляция, не трогает prod service path
**Warning signs:** После тестов `security find-generic-password -s com.govorun.app.credentials` показывает мусор.

### Pitfall 2: Benchmark «cloud vs local» нечестный из-за разных входов

**What goes wrong:** Запустили cloud в audio-in режиме (`processAudio` через WAV upload), local — в text-in режиме (`normalize` через chat). Сравнение «cloud хуже» — потому что local не делает STT, у него идеальный текст на входе.
**Why it happens:** Cloud-2-Max принимает audio через `/files` + `chat/completions` attachments. Local llama-server — text-only. Если sample — текст, нужно одинаково подавать оба.
**How to avoid:** **Симметричный benchmark — text-in для обоих.** Для cloud — `chat/completions` с user content = expected raw transcript из seed. Audio-in benchmarking требует TTS dataset, отложено.
**Warning signs:** Cloud results радикально отличаются от Phase 12 reports (сейчас 80%+) → проверь, что user_content передаётся правильно.

### Pitfall 3: Token rate limit / cost overrun

**What goes wrong:** Запустили benchmark на 36 samples, каждый делает 1-2 OAuth calls + 1 chat completion. Нечётко считаем стоимость → выжгли 50K токенов на debugging вместо production benchmark.
**Why it happens:** GigaChat-2-Max — premium model, 2M token limit на dev plan (Sanya gets free quota). 36 samples × ~500 tokens prompt + ~50 output ≈ 20K tokens на full run. Если retry или multiple runs — быстро накапливается.
**How to avoid:**
- Coalesce OAuth tokens — single token для всего batch (existing SberAuthService паттерн)
- В Plan 3 (run benchmark): сначала dry-run 3-5 samples, проверить format ответа, потом full 36
- В summary: эмитить total token usage из API response usage field (`prompt_tokens`, `completion_tokens`, `total_tokens` уже есть в Sber response)
**Warning signs:** OAuth refresh каждый sample = баг (не должно быть, token cache TTL 30 минут).

### Pitfall 4: SSL/TLS handshake failure на cloud calls в benchmark

**What goes wrong:** Python `urllib.request` при HTTPS вызове к `gigachat.devices.sberbank.ru` падает с `CERTIFICATE_VERIFY_FAILED` — цепочка идёт через российский Минцифры root CA, не доверенный на macOS по умолчанию.
**Why it happens:** Production app использует `SberTrustPolicy` с bundled `SberRootCA.pem` для cert pinning. Benchmark Python скрипт по умолчанию использует system trust store, который НЕ знает Sber root.
**How to avoid:**
- Указать `SberRootCA.pem` через `ssl.create_default_context(cafile=...)` в benchmark
- Расположение PEM в репо: `Govorun/Resources/SberRootCA.pem` (хардкод путь относительно `REPO_ROOT` в скрипте)
- Альтернатива (НЕ рекомендуется): `urllib3.disable_warnings()` + verify=False — небезопасно
**Warning signs:** `ssl.SSLCertVerificationError` в первом cloud вызове benchmark.

### Pitfall 5: Benchmark commits секреты

**What goes wrong:** Sanya забыл добавить `.env.bench` в `.gitignore` и сделал `git add -A`. Client secret уходит в публичный репо.
**Why it happens:** Новый файл, не покрыт существующими ignore patterns.
**How to avoid:**
- Plan 2 явно: первый task — `.gitignore` patch для `.env.bench` и `.env.bench.example` (last template без секретов в репо)
- В benchmark скрипте — assertion на старте: если `--cloud-credentials-env .env.bench` указан, проверить что файл в `.gitignore` (grep) перед чтением
- BENCHMARK-RESULTS.md явно НЕ содержит client_id/secret/token, только агрегаты
**Warning signs:** `git status` показывает `.env.bench` как untracked.

## Code Examples

### Example 1: Real CredentialStore test pattern (Plan 1)

```swift
// GovorunTests/CredentialStoreKeychainTests.swift (NEW)
@testable import Govorun
import XCTest

final class CredentialStoreKeychainTests: XCTestCase {
    private var store: CredentialStore!
    private var testServiceName: String!

    override func setUp() {
        super.setUp()
        // Уникальный service per test — не пересекается с prod Keychain entries
        testServiceName = "com.govorun.tests.\(UUID().uuidString)"
        store = CredentialStore(serviceOverride: testServiceName)
        // ↑ требует добавить serviceOverride: String? = nil в CredentialStore.init
    }

    override func tearDown() {
        // Cleanup на случай если тест упал между save и delete
        try? store.delete()
        super.tearDown()
    }

    func test_save_thenGet_roundtrip() throws {
        try store.save(clientId: "real-id", clientSecret: "real-secret")
        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "real-id")
        XCTAssertEqual(creds?.secret, "real-secret")
    }

    func test_delete_idempotent_whenEmpty() throws {
        // errSecItemNotFound должен tolerated
        XCTAssertNoThrow(try store.delete())
    }

    func test_save_upserts_existing() throws {
        try store.save(clientId: "old", clientSecret: "old-s")
        try store.save(clientId: "new", clientSecret: "new-s")
        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "new")
        XCTAssertEqual(creds?.secret, "new-s")
    }
    // ... 5-7 ещё тестов
}
```

### Example 2: AppStateCloudShim error propagation tests (Plan 1)

```swift
// GovorunTests/AppStateCloudShimTests.swift (EXTEND existing file)

func test_saveCloudCredentials_propagatesStoreError_keepsCloudAvailableFalse() {
    let store = MockCredentialStore()
    store.saveError = CredentialStoreError.saveFailed(-25299)
    let (appState, _) = makeAppState(credentialStore: store)

    XCTAssertThrowsError(try appState.saveCloudCredentials(clientId: "a", clientSecret: "b")) { error in
        XCTAssertEqual(error as? CredentialStoreError, .saveFailed(-25299))
    }
    XCTAssertFalse(appState.cloudAvailable, "cloudAvailable не флипается на true при ошибке save")
}

func test_deleteCloudCredentials_propagatesStoreError() throws {
    let store = MockCredentialStore()
    try store.save(clientId: "x", clientSecret: "y")
    store.deleteError = CredentialStoreError.deleteFailed(-25300)
    let (appState, _) = makeAppState(credentialStore: store)

    XCTAssertThrowsError(try appState.deleteCloudCredentials())
}

func test_probeCloudConnection_wrapsNonAuthErrorIn_networkError() async {
    struct UnexpectedError: Error {}
    let mockAuth = MockAuthService()
    mockAuth.tokenError = UnexpectedError()
    let (appState, _) = makeAppState(credentialStore: MockCredentialStore(), authService: mockAuth)

    let result = await appState.probeCloudConnection()
    guard case .failure(let authError) = result else {
        XCTFail("Ожидался .failure")
        return
    }
    if case .networkError = authError { /* OK */ } else {
        XCTFail("Non-AuthError должен оборачиваться в .networkError, получен \(authError)")
    }
}
```

### Example 3: Benchmark cloud mode CLI extension (Plan 2)

```python
# scripts/benchmark-llm-normalization.py — добавление --mode cloud (концептуально)

def parse_args() -> argparse.Namespace:
    # ... existing args ...
    parser.add_argument("--mode", choices=["local", "cloud"], default="local",
                        help="Backend: 'local' (llama-server) or 'cloud' (Sber GigaChat)")
    parser.add_argument("--cloud-base-url", default="https://gigachat.devices.sberbank.ru/api/v1")
    parser.add_argument("--cloud-model", default="GigaChat-2-Max")
    parser.add_argument("--cloud-credentials-env", default=".env.bench")
    parser.add_argument("--cloud-token-url",
                        default="https://ngw.devices.sberbank.ru:9443/api/v2/oauth")
    parser.add_argument("--cloud-cert-path", default="Govorun/Resources/SberRootCA.pem")

def load_cloud_credentials(env_path: Path) -> tuple[str, str]:
    if not env_path.exists():
        raise BenchmarkConfigurationError(f"Cloud credentials file not found: {env_path}")
    creds = {}
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            creds[k.strip()] = v.strip().strip('"').strip("'")
    cid = creds.get("SBER_CLIENT_ID")
    secret = creds.get("SBER_CLIENT_SECRET")
    if not cid or not secret:
        raise BenchmarkConfigurationError(f"{env_path} must contain SBER_CLIENT_ID and SBER_CLIENT_SECRET")
    return cid, secret

# In-process token cache
_TOKEN_CACHE = {"access_token": None, "expires_at": 0.0}

def obtain_sber_token(*, token_url: str, client_id: str, secret: str, cert_path: Path) -> str:
    now = time.time()
    if _TOKEN_CACHE["access_token"] and _TOKEN_CACHE["expires_at"] > now + 300:
        return _TOKEN_CACHE["access_token"]

    auth_header = base64.b64encode(f"{client_id}:{secret}".encode()).decode()
    body = "scope=GIGACHAT_API_PERS".encode()
    request = urllib.request.Request(
        url=token_url, data=body, method="POST",
        headers={
            "Authorization": f"Basic {auth_header}",
            "RqUID": str(uuid.uuid4()),
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
    )
    ssl_ctx = ssl.create_default_context(cafile=str(cert_path))
    with urllib.request.urlopen(request, context=ssl_ctx, timeout=30) as resp:
        payload = json.loads(resp.read())
    token = payload["access_token"]
    expires_at_ms = payload["expires_at"]
    _TOKEN_CACHE["access_token"] = token
    _TOKEN_CACHE["expires_at"] = expires_at_ms / 1000.0
    return token
```

### Example 4: BENCHMARK-RESULTS.md template (Plan 2 deliverable)

```markdown
# Cloud vs Local Quality Benchmark — 2026-04-XX

**Дата:** YYYY-MM-DD
**Железо:** Apple M1, 16GB RAM, macOS 14.x
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples)
**Модели сравниваются:**
- Cloud: `GigaChat-2-Max` (Sber API, temperature=0.1)
- Local: `GigaChat 3.1 10B-A1.8B Q4_K_M` (llama-server, temperature=0)

## Команды

```bash
# Local baseline
python3 scripts/benchmark-llm-normalization.py \
  --mode local --pipeline-mode full-pipeline \
  --base-url http://127.0.0.1:8080/v1 --model gigachat-gguf \
  --super-style normal --warmup 0 \
  --output build/bench-local-2026-04-XX.jsonl \
  --summary build/bench-local-2026-04-XX-summary.json

# Cloud comparison
python3 scripts/benchmark-llm-normalization.py \
  --mode cloud --pipeline-mode full-pipeline \
  --cloud-credentials-env .env.bench \
  --super-style normal --warmup 0 \
  --output build/bench-cloud-2026-04-XX.jsonl \
  --summary build/bench-cloud-2026-04-XX-summary.json
```

## Результаты

| Метрика | Local (GigaChat 3.1 Q4) | Cloud (GigaChat-2-Max) | Δ |
|---------|-------------------------|------------------------|---|
| Exact match end-to-end | XX.X% | XX.X% | +/-X.X pp |
| Period-tolerant match | XX.X% | XX.X% | +/-X.X pp |
| Short bucket (12) | XX.X% | XX.X% | +/-X.X pp |
| Medium bucket (12) | XX.X% | XX.X% | +/-X.X pp |
| Long bucket (12) | XX.X% | XX.X% | +/-X.X pp |
| llmRejected (Gate) | X | X | — |
| Errors | X | X | — |
| Total tokens used (Cloud) | — | XXX,XXX (~$X.XX equiv) | — |

## Failures Comparison

### Cloud-only failures (succeeded local)
- `[id]` — expected: `...`, cloud got: `...`

### Local-only failures (succeeded cloud)
- `[id]` — expected: `...`, local got: `...`

### Both failed
- `[id]` — expected: `...`, local: `...`, cloud: `...`

## Анализ

[Что cloud делает лучше / хуже local. Длинные предложения? Сложные перечисления? Самокоррекция?]

## Рекомендация для Phase 17

[Cloud rollout default-on / default-off / requires UI nudge / ...]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `MockCredentialStore` only — Keychain implementation untested | Real `CredentialStore` integration tests with unique service-suffix per test | Phase 16 Plan 1 | Catches Keychain edge cases (errSecDuplicateItem, errSecItemNotFound) at unit level |
| Helper «сломан после TextMode removal» (CONTEXT claim) | Helper мигрирован, компилируется и работает; legacy `--text-mode` deprecated alias живёт для backwards compat | Verified 2026-04-23 by direct compile | Никаких repair действий. Phase 16 plan не должен включать «починить helper» |
| Benchmark — local-only | Benchmark `--mode {local, cloud}` с symmetric text-in input | Phase 16 Plan 2 | Apples-to-apples сравнение нормализации, без TTS scope creep |
| Cloud quality unknown vs local | Documented в `16-BENCHMARK-RESULTS.md` с per-bucket breakdown + failures comparison | Phase 16 Plan 3 | Sanya принимает информированное решение про default Cloud в Phase 17 rollout |

**Deprecated/outdated (не делать в Phase 16):**
- TextMode-based benchmark API — уже удалён из helper в v1.0, не воскрешать
- Streaming SSE для cloud если Sber не поддерживает — fallback на non-streaming JSON, не блокер

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GigaChat-2-Max через `/chat/completions` поддерживает text-in (без attachments) | Benchmark Script Audit, Pitfall 2 | Если только audio-in — symmetric benchmark невозможен без TTS scope creep. Mitigate: smoke test первым делом в Plan 3 (1 sample dry-run) |
| A2 | Sber API возвращает `usage.total_tokens` в response для cost tracking | Pitfall 3 | Если нет — token accounting только grep по логам Sber dev console. Не блокер, nice-to-have |
| A3 | `SberRootCA.pem` cert path работает с Python `ssl.create_default_context(cafile=...)` | Pitfall 4 | Если PEM формат не совместим — fallback на `verify=False` (security risk, не рекомендуется) или альтернативно конвертация PEM→DER |
| A4 | `CredentialStore` в production использует hardcoded `Keys.service = "com.govorun.app.credentials"` — тесты с UUID-suffix не пересекутся с prod если приложение не запущено в parallel | Pitfall 1, Plan 1 | Низкий риск (CI и dev environment отдельные). Mitigate: tearDown гарантирует cleanup |
| A5 | Sanya хочет benchmark только в `full-pipeline` mode (не `llm-only`) | Validation Architecture | Если хочет оба — Plan 3 делает 4 прогона (local llm-only, local full-pipeline, cloud llm-only, cloud full-pipeline). Surface choice в Plan 3 |
| A6 | 2M token GigaChat Max free quota хватит на 5-10 benchmark прогонов | Pitfall 3 | Каждый full run ≈20-30K tokens = ≈1% quota. Margin huge. Низкий риск |

**Если этот раздел НЕ пуст** — Plan 2/3 первой задачей делает A1+A3 smoke-test (1-2 sample cloud call), surface findings перед full benchmark.

## Open Questions (SURFACED AS CHECKPOINTS)

1. **Какой scope cloud benchmark — text-in или audio-in?** → Plan 3 Task 1 checkpoint:decision (option-a/b/c)
   - Что мы знаем: Cloud production использует audio-in (`processAudio` через `/files` upload). Local production использует text-in (после STT). Seed dataset — текстовые inputs.
   - Что неясно: Sanya хочет «честное сравнение качества нормализации» (text-in для обоих, симметрично) или «реалистичное product-level сравнение» (cloud audio-in vs local text-in после STT, асимметрично)?
   - Recommendation: **text-in symmetric** в Phase 16. Audio-in benchmark — отдельная аналитика латентности в Phase 17 (CLOUD-06).

2. **Использовать prod GigaChat client_id или создавать отдельный bench client?** → Plan 2 Task 1 checkpoint:decision (option-a/b)
   - Что мы знаем: CONTEXT.md явно: «Sanya решает».
   - Что неясно: rate limit shared между prod и bench → может задеть real users если оба активны.
   - Recommendation: surface в Plan 2 как первый task — «создать `.env.bench` template, попросить Sanya задизайнить scope». Дефолт — отдельный client (изоляция blast radius).

3. **Делать ли LLM-as-judge eval для качественных failures?** → RESOLVED: out of scope Phase 16
   - Что мы знаем: existing scoring — exact match + period-tolerant. Длинные предложения часто failing на pure string match даже когда semantically correct.
   - Что неясно: Sanya может захотеть качественный анализ failures с GPT-4 или Claude scoring.
   - Recommendation: **out of scope Phase 16.** Document failures в `16-BENCHMARK-RESULTS.md`, дать Sanya вручную просмотреть. LLM-judge — отдельный future eval system.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `xcodebuild` | All Swift tests | ✓ (assumed via Xcode 15.4) | 15.4 per project.yml | None — required |
| `python3` | benchmark script | ✓ | 3.13 (system or embedded) | None — required |
| Python `urllib.request`, `argparse`, `ssl` | Benchmark cloud + local | ✓ stdlib | — | None |
| `xcrun swiftc` | benchmark-full-pipeline-helper compilation | ✓ verified by compile test | 5.10 | None — required |
| `llama-server` running on :8080 | Benchmark `--mode local` | Start via `bash scripts/build-llama-server.sh` + `bash scripts/run-gigachat-llm.sh` | b8500 | Skip local mode, run cloud-only (less informative) |
| GigaChat 3.1 GGUF model loaded | Benchmark `--mode local` | `~/.govorun/models/gigachat-gguf.gguf` (auto-downloaded by app или manual) | per `SuperModelCatalog.current` | Same — skip local |
| Sber API connectivity | Benchmark `--mode cloud` | UAT 2026-04-22 confirmed prod round-trip | — | Skip cloud benchmark, document blocker |
| `.env.bench` with credentials | Benchmark `--mode cloud` | ✗ (not created — Plan 2 first task) | — | Manual entry of `--cloud-client-id` / `--cloud-client-secret` (NOT recommended — leaks via shell history) |
| `Govorun/Resources/SberRootCA.pem` | Benchmark `--mode cloud` SSL | ✓ (bundled in app, source-controlled) | Per Phase 10 | Use `urllib3` `verify=False` (security risk, NOT recommended) |

**Missing dependencies with no fallback:** xcodebuild, python3, swiftc — all expected on Sanya's M1 dev machine.

**Missing dependencies with fallback:**
- `.env.bench` — Plan 2 первый task создаёт `.env.bench.example` template + adds `.env.bench` to `.gitignore`. Sanya копирует example → сам заполняет credentials.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Apple, bundled with Xcode 15.4) |
| Config file | `Govorun.xctestplan` (skips `LLMQualityEvalTests` per existing config) |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/CredentialStoreKeychainTests` (per-suite filter) |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| Test count baseline | 1299 (per STATE.md, verified via `grep -c "func test_"`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | CredentialStore Keychain implementation correct (save/get/delete/upsert/idempotent delete) | unit | `xcodebuild test -only-testing:GovorunTests/CredentialStoreKeychainTests` | ❌ — Plan 1 |
| TEST-01 | AppStateCloudShim error propagation для CredentialStoreError | unit | `xcodebuild test -only-testing:GovorunTests/AppStateCloudShimTests/test_saveCloudCredentials_propagatesStoreError_keepsCloudAvailableFalse` (etc.) | ❌ — Plan 1 (extends existing file) |
| TEST-01 | (optional) CloudLLMClient `function_call` injection + URLError mapping | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/test_processAudio_includesFunctionCallAuto_whenAttachments` (etc.) | ❌ — Plan 1 (optional, extends existing file) |
| TEST-01 | Full coverage check: 1299+ baseline tests still PASS after additions | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS'` | ✅ — full suite |
| TEST-02 | benchmark-llm-normalization.py supports `--mode cloud` flag | manual run | `python3 scripts/benchmark-llm-normalization.py --mode cloud --help` (smoke) + dry-run 1 sample | ❌ — Plan 2 |
| TEST-02 | `16-BENCHMARK-RESULTS.md` exists with cloud + local results table | doc check | `test -f .planning/phases/16-tests/16-BENCHMARK-RESULTS.md && grep -q 'GigaChat-2-Max' .planning/phases/16-tests/16-BENCHMARK-RESULTS.md` | ❌ — Plan 3 |

### Sampling Rate

- **Per task commit:** Run only the suite touched by that task: `xcodebuild test -only-testing:GovorunTests/{TouchedTests}`
- **Per wave / plan merge:** Run full suite: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`. Must show **1299 + N PASS** where N = new test count for that plan.
- **Phase gate (`/gsd-verify-work`):** Full suite green + benchmark dry-run smoke (cloud + local each return at least one result without 500/auth errors).

### Phase Acceptance Signals (beyond «1299+ tests pass»)

Phase 16 «done» when ALL of:
1. ✅ Full suite XCTest passes (≈1310-1314 tests after Plan 1 additions)
2. ✅ `scripts/benchmark-llm-normalization.py --mode cloud --help` exits 0 (CLI parses new flags)
3. ✅ `scripts/benchmark-llm-normalization.py --mode cloud` smoke-runs successfully against real Sber API (1+ sample completes without auth/SSL/transport error)
4. ✅ `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md` exists with:
   - Local results from Phase 16 prog run (not from old benchmarks/reports/)
   - Cloud results from Phase 16 prog run
   - Side-by-side metric table (exact match, period-tolerant, per-bucket)
   - Failures comparison section
   - «Анализ» paragraph (Sanya's call) — даже placeholder допустим
5. ✅ ROADMAP.md TEST-01 + TEST-02 checkboxes flipped from `[ ]` to `[x]`
6. ✅ `.env.bench` confirmed in `.gitignore`, no credentials in git history
7. ✅ STATE.md updated: Phase 16 → CLOSED

### Wave 0 Gaps

- [ ] `GovorunTests/CredentialStoreKeychainTests.swift` — covers TEST-01 (real Keychain)
- [ ] Extend `GovorunTests/AppStateCloudShimTests.swift` — covers TEST-01 (error propagation)
- [ ] (optional) Extend `GovorunTests/CloudLLMClientTests.swift` — covers TEST-01 minor gaps
- [ ] `scripts/benchmark-llm-normalization.py` — extend with `--mode cloud` flag + helpers (Plan 2)
- [ ] `.env.bench.example` — template (no real secrets)
- [ ] `.gitignore` patch — add `.env.bench`
- [ ] `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md` — created by Plan 3
- [ ] `Govorun/Storage/CredentialStore.swift` — добавить `init(serviceOverride: String? = nil)` для testability (если выбрана Option A в Pitfall 1)

*Existing test infrastructure (MockHTTPClient, MockAuthService, MockCredentialStore, MockTrustPolicy, MockCloudAudioClient, MockNetworkAvailability, SequentialMockHTTPClient) полностью покрывает all новые tests — никаких новых mock helpers не требуется.*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Production: SberAuthService OAuth (existing). Tests: MockAuthService — без real network |
| V3 Session Management | n/a | No HTTP sessions in unit tests |
| V4 Access Control | yes | CredentialStore — Keychain ACL по умолчанию (kSecAttrAccessibleWhenUnlocked default) |
| V5 Input Validation | partial | Tests verify URL guards (H-01 fix), AuthError mapping. Benchmark validates dataset format on load |
| V6 Cryptography | yes | TLS pinning через SberTrustPolicy — production tested. Benchmark uses cafile= для cert verify |
| V7 Error Handling | yes | All cloud error paths covered: cloudErrorMessage, AuthError mapping, LLMError mapping. Plan 1 closes shim error propagation gap |
| V8 Data Protection | yes | Secrets: client_id/secret в Keychain (prod), `.env.bench` (.gitignore'd, bench-only). Никогда в logs (15-REVIEW PASS) |
| V14 Configuration | yes | `.env.bench` mode separate from prod credentials — Sanya разделяет |

### Known Threat Patterns for {Swift macOS app + Python benchmark}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Credentials leaked в git via `.env.bench` accidental commit | Information Disclosure | Plan 2 task 1: `.gitignore` patch + assertion in benchmark script that `.env.bench` matches a `.gitignore` line |
| Test pollution of system Keychain | Tampering (data) | Plan 1: `init(serviceOverride: String? = nil)` DI — tests use UUID-suffixed service identifier |
| Cloud benchmark calls leak audio/transcripts to logs | Information Disclosure | BENCHMARK-RESULTS.md only aggregates; per-sample raw outputs stay local в `build/*.jsonl` (build/ already in .gitignore) |
| TLS bypass in benchmark (verify=False) | Spoofing | Plan 2 explicit: use `cafile=Govorun/Resources/SberRootCA.pem`, NEVER `verify=False` |
| Token theft via in-memory dump | Information Disclosure | Out of scope (process-level dump = full system compromise). Token cached в module-level dict, не на disk |
| Rate-limit DoS during benchmark | DoS (self-inflicted) | Plan 3 first task: dry-run 1 sample. Existing OAuth coalesce already in place. Surface token usage в benchmark output |

## Sources

### Primary (HIGH confidence)
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/phases/16-tests/16-CONTEXT.md` — User decisions, locked
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/REQUIREMENTS.md` — TEST-01, TEST-02 specs
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/STATE.md` — 1299 tests baseline, Phase 15 closed
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/ROADMAP.md` — Phase 16 success criteria
- `/Users/sanyasamineva/Desktop/govorun-app/CLAUDE.md` — Project conventions (TDD, mocks-only, etc.)
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/config.json` — `nyquist_validation: true` confirmed
- `/Users/sanyasamineva/Desktop/govorun-app/Govorun.xctestplan` — XCTest config, skips LLMQualityEvalTests
- All cloud-related Swift sources (CloudLLMClient, SberAuthService, SberTrustPolicy, CredentialStore, NetworkMonitor, PipelineEngine, AppState, CloudErrorCopy, ProductMode) — read end-to-end
- All cloud-related test sources (CloudLLMClientTests, SberAuthServiceTests, CredentialStoreTests, SberTrustPolicyTests, AppStateCloudShimTests, CloudSettingsErrorMessageTests, NetworkAvailabilityTests, IntegrationTests, ProductModeTests, SettingsStoreTests cloud sections, PipelineEngineTests cloud sections) — read end-to-end
- `scripts/benchmark-llm-normalization.py` — full file (981 lines)
- `scripts/benchmark-full-pipeline-helper.swift` — full file + verified compile + verified runtime via smoke test
- `benchmarks/README.md` + `benchmarks/llm-normalization-seed.jsonl` (head) + `benchmarks/reports/2026-04-04-full-pipeline-normal-postfix-m1-16gb.md`
- `.claude/skills/benchmark/SKILL.md` + `.claude/skills/verify/SKILL.md`
- `.planning/phases/15-cloud-settings-ui/15-REVIEW.md` + `15-REVIEW-FIX.md` — Phase 15 closure context

### Secondary (MEDIUM confidence)
- Knowledge of Apple Keychain Services API (SecItem*) — used to assess CredentialStore implementation correctness
- Knowledge of GigaChat-2-Max API contract (Bearer auth, /chat/completions, /files upload, RqUID header) — verified through CloudLLMClient implementation reading
- Sber Минцифры root CA bundling pattern — confirmed by SberTrustPolicy reading

### Tertiary (LOW confidence)
- Sber GigaChat free tier 2M token quota for `GigaChat-2-Max` — from MEMORY.md `project_gigachat_cloud.md`. Not independently verified against developers.sber.ru policy page.
- Cloud SSE streaming support specifics — assumed compatible with OpenAI streaming format. Smoke test in Plan 3 will confirm.

## Metadata

**Confidence breakdown:**
- Coverage gap analysis: HIGH — direct file reads, grep counts, cross-referenced
- Benchmark script audit: HIGH — full file read, helper compiled and ran
- Validation architecture: HIGH — known commands, known XCTest framework
- Cloud API integration assumptions (A1-A6): MEDIUM — based on existing Swift code patterns; smoke test in Plan 3 validates

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 (30 days for stable; cloud API endpoints + Sber root CA — stable; XCTest framework — stable)
