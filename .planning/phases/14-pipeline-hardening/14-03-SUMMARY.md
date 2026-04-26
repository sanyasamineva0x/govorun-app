---
# [skip-review: per-plan SUMMARY is a reporting artifact; Codex review happens at end-of-phase cumulative diff (plan 14-04), not per-plan]
phase: 14-pipeline-hardening
plan: 03
subsystem: pipeline
tags: [network, pipeline, di, protocol, tdd]
requirements: [MODE-05]
dependency_graph:
  requires:
    - "Plan 14-01 (SnippetReinserter.cleanSubstitute) — independent, но обе часть Phase 14 wave 1-2"
  provides:
    - "protocol NetworkAvailabilityProviding: Sendable"
    - "PipelineEngine.init(networkAvailability:) параметр (optional, default nil)"
    - "MockNetworkAvailability для тестов Phase 14-04"
  affects:
    - "Govorun/Core/NetworkMonitor.swift (+ protocol, class conformance)"
    - "Govorun/Core/PipelineEngine.swift (+ init param, + storage, + accessor)"
    - "Govorun/App/AppState.swift (production DI wiring)"
tech_stack:
  added: []
  patterns:
    - "optional DI параметр с default nil — zero regression для существующих callsites"
    - "storage под NSLock consistent с _cloudClient паттерном"
    - "@unchecked Sendable + NetworkAvailabilityProviding, @unchecked Sendable в class declaration без extension"
    - "Sendable protocol → conformers обязаны быть Sendable-safe"
key_files:
  created:
    - path: "GovorunTests/NetworkAvailabilityTests.swift"
      purpose: "MockNetworkAvailability + 7 unit-тестов (protocol conformance, mock behaviour, PipelineEngine DI)"
  modified:
    - path: "Govorun/Core/NetworkMonitor.swift"
      change: "+10 строк: protocol NetworkAvailabilityProviding: Sendable + class conformance"
    - path: "Govorun/Core/PipelineEngine.swift"
      change: "+11 строк: storage _networkAvailability + init param + currentNetworkAvailability() accessor"
    - path: "Govorun/App/AppState.swift"
      change: "+1 строка: networkAvailability: networkMonitor в PipelineEngine init"
decisions:
  - "Protocol стратегия (D-09b), не closure — consistency с STTClient/LLMClient/CloudAudioProcessing/SnippetMatching DI паттерном"
  - "Протокол размещён в том же файле что и NetworkMonitor — тонкий wrapper, отдельный файл не оправдан"
  - "NetworkMonitor class conformance через class declaration (не extension) — одна декларация ObservableObject + NetworkAvailabilityProviding + @unchecked Sendable"
  - "networkAvailability параметр в КОНЦЕ списка init — сохраняет все existing positional и named callsites (60+ тестов и production code)"
  - "Default nil трактуется как 'сеть доступна' (offline fallback только при явном false) — Plan 14-04 будет fallback только при isCurrentlyConnected == false"
  - "Happy-path test настраивает stt.recognizeResult явно — без этого MockSTTClient throws STTError.noResult, и тест ловит его вместо проверки nil provider не crash"
metrics:
  duration: "~4m"
  completed: "2026-04-19T23:27:00+03:00"
  tests_added: 7
  tests_passing: 1270  # full suite
---

# Phase 14 Plan 03: NetworkAvailabilityProviding Injection Summary

**One-liner:** Введён тонкий протокол `NetworkAvailabilityProviding: Sendable` (read-only `isCurrentlyConnected`), `NetworkMonitor` конформит ему через class declaration, `PipelineEngine` принимает опциональный провайдер через init (default nil, zero regression), `AppState` production init передаёт `networkMonitor`. Никакого изменения поведения — только infrastructure для Plan 14-04.

## Objective Met

Infrastructure для offline fast-fail в cloud path (D-09) готова:

- Тестируемость: `MockNetworkAvailability` можно инжектить в PipelineEngine тесты через init
- Consistency: Protocol-based DI в том же стиле, что STTClient, LLMClient, CloudAudioProcessing, SnippetMatching
- Backward compat: default nil — все 1263 существующих теста продолжают работать без модификаций callsites
- Production wired: `AppState` передаёт единственный существующий `NetworkMonitor` экземпляр в `PipelineEngine`, готово к чтению в 14-04

Plan 14-04 (последний в фазе) вычитает `currentNetworkAvailability()?.isCurrentlyConnected` в начале `processCloudPath` и при `== false` маршрутизирует на local STT flow с info-toast «Нет сети — использую локальную обработку» (D-09a).

## Implementation

### 1. `protocol NetworkAvailabilityProviding: Sendable`

```swift
// Govorun/Core/NetworkMonitor.swift

protocol NetworkAvailabilityProviding: Sendable {
    var isCurrentlyConnected: Bool { get }
}

final class NetworkMonitor: ObservableObject, NetworkAvailabilityProviding, @unchecked Sendable {
    @Published private(set) var isConnected = false
    private let monitor = NWPathMonitor()

    var isCurrentlyConnected: Bool {
        monitor.currentPath.status == .satisfied
    }

    // ... init/deinit unchanged ...
}
```

**Sendable:** Протокол Sendable. `NetworkMonitor` — `final class` с `@unchecked Sendable`, доверяем что `NWPathMonitor.currentPath.status` thread-safe (Apple documented). Никаких мутаций при чтении.

**Поведение не изменилось:** Публичное API `isConnected @Published` и `isCurrentlyConnected` осталось точно тем же, только теперь оба конформятся через Protocol.

### 2. PipelineEngine DI

```swift
// Govorun/Core/PipelineEngine.swift

// Storage (после _cloudClient):
private var _networkAvailability: NetworkAvailabilityProviding?

// Init (новый параметр В КОНЦЕ):
init(
    audioCapture: AudioRecording,
    sttClient: STTClient,
    llmClient: LLMClient,
    snippetEngine: SnippetMatching? = nil,
    saveAudioFile: (@Sendable (Data, UUID) throws -> String)? = nil,
    deleteAudioFile: (@Sendable (String) -> Void)? = nil,
    networkAvailability: NetworkAvailabilityProviding? = nil  // NEW
) {
    // ... existing ...
    _networkAvailability = networkAvailability  // NEW
    // ... existing ...
}

// Accessor (рядом с currentIsCancelled, для Plan 14-04):
private func currentNetworkAvailability() -> NetworkAvailabilityProviding? {
    lock.lock()
    defer { lock.unlock() }
    return _networkAvailability
}
```

**Lock convention:** consistent с `_cloudClient`, `_llmClient`, `_hints` и другими mutable state в PipelineEngine.

**Accessor private:** Plan 14-04 вызовет его из `processCloudPath` — внутренняя утилита, не часть публичного API.

### 3. AppState production wiring

```swift
// Govorun/App/AppState.swift (в init)

pipelineEngine = PipelineEngine(
    audioCapture: audio,
    sttClient: stt,
    llmClient: llm,
    snippetEngine: snippetEngine,
    networkAvailability: networkMonitor  // NEW — networkMonitor уже существует как let (строка 103)
)
```

`networkMonitor` — существующий `let networkMonitor = NetworkMonitor()` в AppState (строка 103). Теперь один и тот же инстанс used для двух целей:

1. Published `@ObservableObject` для UI (будет использован в Phase 15 settings для offline indicator)
2. Pipeline injection для offline fast-fail

Нет двойного allocation NetworkMonitor — одна система наблюдения за сетью.

**Test init AppState не затронут:** Тесты AppState инжектят pipelineEngine как готовый объект через test init, не через production init path.

## Tests

### `NetworkAvailabilityProvidingTests` (7 тестов)

1. `test_networkMonitor_conforms_to_providing_protocol` — compile-check: `let provider: NetworkAvailabilityProviding = NetworkMonitor()` работает
2. `test_mockNetworkAvailability_returns_configured_true` — `init(connected: true)` → `isCurrentlyConnected == true`
3. `test_mockNetworkAvailability_returns_configured_false` — `init(connected: false)` → `isCurrentlyConnected == false`
4. `test_mockNetworkAvailability_setConnected_updates_value` — mutator работает, sequence false → true
5. `test_pipelineEngine_accepts_network_availability_via_init` — `PipelineEngine(... networkAvailability: mock)` компилится
6. `test_pipelineEngine_default_networkAvailability_is_nil_compile_check` — `PipelineEngine(audioCapture:, sttClient:, llmClient:)` (без нового параметра) компилится
7. `test_pipelineEngine_with_nil_provider_does_not_crash_in_startStop` — start → stop happy path проходит с nil provider

### `MockNetworkAvailability` (готов для 14-04)

```swift
final class MockNetworkAvailability: NetworkAvailabilityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _connected: Bool

    init(connected: Bool = true) { _connected = connected }

    var isCurrentlyConnected: Bool {
        lock.lock(); defer { lock.unlock() }; return _connected
    }

    func setConnected(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }; _connected = value
    }
}
```

Thread-safe, `setConnected` позволит тестам в 14-04 симулировать network drop посреди операции.

### Итоги выполнения

- **Новые тесты:** 7 PASS (NetworkAvailabilityProvidingTests)
- **Регрессия:** 1270 тестов (full suite) — 0 failures
  - PipelineEngineTests: 37 PASS (nil default preserves all callsites)
  - +7 новых → 1270 total (было 1263 в 14-02)

## Deviations from Plan

### Auto-fixed Issues

**1. `[Rule 1 - Bug]` Happy-path тест бросал `STTError.noResult` вместо проверки nil provider**

- **Found during:** Task 2 (GREEN) после первого запуска тестов
- **Issue:** `test_pipelineEngine_with_nil_provider_does_not_crash_in_startStop` создавал `MockSTTClient()` без `recognizeResult`. При `stopRecording()` `MockSTTClient.recognize` находил `recognizeResult == nil` и бросал `STTError.noResult`, что PipelineEngine оборачивал в `PipelineError.sttFailed`. Тест падал на `try await engine.stopRecording()` с ошибкой — а должен был проверить, что nil provider не ломает happy path.
- **Fix:** Настроил `stt.recognizeResult = STTResult(text: "привет")` — теперь STT успешен, тест проходит через весь pipeline и верифицирует, что nil `NetworkAvailabilityProviding` не мешает start→stop flow.
- **Files modified:** `GovorunTests/NetworkAvailabilityTests.swift`
- **Commit:** `663b8dc` (амальгамирован в GREEN commit)

### Non-auto-fix

Нет. План исполнен точно по спецификации.

## TDD Gate Compliance

| Gate     | Commit    | Status |
| -------- | --------- | ------ |
| RED      | `05b6d7c` | test(14-03): 7 failing тестов, compile fails с `cannot find type 'NetworkAvailabilityProviding'` и `extra argument 'networkAvailability' in call` |
| GREEN    | `663b8dc` | feat(14-03): протокол + DI + AppState wiring — 7 новых тестов PASS, 0 регрессий (1270 total) |
| REFACTOR | —         | не потребовался (минимальные изменения, идиоматичный код) |

## Commits

1. `05b6d7c` — `test(14-03): failing тесты NetworkAvailabilityProviding и PipelineEngine DI`
2. `663b8dc` — `feat(14-03): NetworkAvailabilityProviding протокол + PipelineEngine DI`

## Known Stubs

Протокол и DI полностью реализованы, но **использование в `processCloudPath` отсутствует** — это ожидаемый state. Plan 14-04 (последний в фазе) добавит чтение `currentNetworkAvailability()?.isCurrentlyConnected` в начале `processCloudPath` и маршрутизацию на local STT при offline.

`_networkAvailability` в текущем коде **writes only** (из init) — никто не reads до Plan 14-04. Это намеренный split: infrastructure отдельно от поведения, каждая часть testable independently.

## Threat Flags

Нет. Протокол читает существующее `NetworkMonitor.isCurrentlyConnected` свойство, которое уже существовало до этой фазы. Никаких новых network/auth/file-access поверхностей. Sendable protocol enforces thread-safe конформанс.

## Self-Check: PASSED

- `Govorun/Core/NetworkMonitor.swift` FOUND (grep "protocol NetworkAvailabilityProviding: Sendable" → 1 hit; grep "NetworkAvailabilityProviding" → 3 hits: protocol decl + class conformance + one isCurrentlyConnected в теле протокола)
- `Govorun/Core/PipelineEngine.swift` FOUND (grep "networkAvailability: NetworkAvailabilityProviding?" → 2 hits: param + storage; grep "_networkAvailability" → 3 hits: declaration + init assignment + accessor)
- `Govorun/App/AppState.swift` FOUND (grep "networkAvailability: networkMonitor" → 1 hit)
- `GovorunTests/NetworkAvailabilityTests.swift` FOUND (grep "class MockNetworkAvailability" → 1 hit; grep "class NetworkAvailabilityProvidingTests" → 1 hit; grep "func test_" → 7 hits)
- Commit `05b6d7c` FOUND (git log)
- Commit `663b8dc` FOUND (git log)
- Все тесты PASS: 1270 в full suite, 0 failures (7 новых + 1263 существующих)
- Post-commit deletion check: 0 файлов удалено GREEN commit
- NetworkMonitor.swift behaviour не изменился: `isConnected @Published` и `isCurrentlyConnected` — те же, добавлен только protocol conformance
