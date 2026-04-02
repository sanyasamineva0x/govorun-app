# Архитектура Говоруна

## Паттерн

Layered architecture с жёсткими правилами импортов. Composition root в `AppState`. Протоколы для всех сервисов — DI через инициализаторы, не глобальные синглтоны.

Все сервисы через протоколы → моки в тестах. Никакого реального Python worker или LLM в тестах.

## Слои

```
GovorunApp.swift (entry point)
    └── AppDelegate
         └── AppState (composition root, @MainActor)
              ├── App/        — UI shell, event tap, AX, window management
              ├── Core/       — бизнес-логика, чистый Swift, нет SwiftUI/AppKit
              ├── Services/   — внешние интеграции (Python IPC, HTTP, Sparkle)
              ├── Models/     — value types, SwiftData models, enums
              ├── Storage/    — SwiftData CRUD, MetricsAggregator
              └── Views/      — SwiftUI views (настройки, онбординг)
```

**Правила импортов (enforced by convention, documented in CLAUDE.md):**
- `Core/` — нет SwiftUI, нет AppKit
- `Services/` — нет AppKit
- `Models/` — чистые value types
- `App/` — AppKit + SwiftUI, системные интеграции

## Точки входа

**Swift:**
- `Govorun/GovorunApp.swift` — `@main struct GovorunApp: App`. LSUIElement=true, menu bar only.
- `applicationDidFinishLaunching` в `AppDelegate` — создаёт `SettingsStore`, `AppState`, `StatusBarController`; показывает онбординг если нужно, затем `state.start()`

**Python worker:**
- `worker/server.py` — unix socket сервер. Запускается `ASRWorkerManager` как дочерний процесс через embedded `Frameworks/Python.framework`

## Composition Root: AppState

`Govorun/App/AppState.swift` (48 KB, ~1400 строк) — центральный объект.

Создаёт и хранит все сервисы:
```swift
ASRWorkerManager → socketPath → LocalSTTClient → PipelineEngine
LLMRuntimeManager (llama-server process)
LocalLLMClient (HTTP → llama-server)
SuperAssetsManager (проверяет binary + GGUF на диске)
SuperModelDownloadManager (скачивание GGUF с HF)
AudioCapture
ActivationKeyMonitor
SessionManager
TextInserterEngine
BottomBarController
AppContextEngine
SnippetEngine + SnippetStore
AnalyticsService
PostInsertionMonitor
UpdaterService (Sparkle)
SettingsStore
```

Wiring выполнен через `wire*()` методы (8 штук):
- `wireActivationKeyMonitor()` — активация/деактивация → `SessionManager`
- `wireSessionManager()` — переходы состояний → pipeline/UI
- `wireAudioCapture()` — делегат AudioCapture → AppState
- `wireSnippetNotifications()` — NSNotification при изменении сниппетов
- `wireWorkerManager()` — состояние Python worker → `@Published workerState`
- `wireLLMRuntimeManager()` — состояние llama-server → `@Published llmRuntimeState`
- `wireSettingsChange()` — изменения SettingsStore (Combine) → pending settings
- `wireSleepNotification()` — системный sleep/wake → пауза worker

**Pending settings pattern:** изменения activationKey, productMode, recordingMode, LLMConfiguration не применяются немедленно — откладываются в `pending*` переменные и применяются только когда `sessionState == .idle`.

## Pipeline (основной путь данных)

```
Activation key (⌥ / кастомная)
    → ActivationKeyMonitor.onActivated
    → AppState.handleActivated()
    → SessionManager: idle → recording
    → AudioCapture.startRecording()          [AVFoundation, 16kHz PCM mono]
    → (пользователь отпускает клавишу)
    → ActivationKeyMonitor.onDeactivated
    → AppState.handleDeactivated()
    → SessionManager: recording → processing
    → AudioCapture.stopRecording() → Data
    → PipelineEngine.process(audioData:)     [async Task]
        → STTClient.recognize(audioData:hints:) → STTResult
            → LocalSTTClient → unix socket (~/.govorun/worker.sock)
            → Python worker: GigaAM-v3 e2e_rnnt (ONNX) + Silero VAD
            → {"text": "распознанный текст"}
        → SnippetEngine.match(rawText) → SnippetMatch?
        → NormalizationPipeline.normalize(text, mode, hints, llmClient, snippetMatch)
            ┌─ Standard mode ──────────────────────────────────────────────────┐
            │  DeterministicNormalizer.normalize():                            │
            │    1. Удалить филлеры (ну, эм, типа, ...)                       │
            │    2. NumberNormalizer.normalize() — числа словами → цифры      │
            │    3. Капитализация после .?!                                    │
            │    4. canonicalizeSurfaceForms() — Jira/Slack/GitHub/PDF...     │
            │    5. Terminal period (если включён)                             │
            └──────────────────────────────────────────────────────────────────┘
            ┌─ Super mode (LLM path) ───────────────────────────────────────────┐
            │  1. Deterministic pre-processing                                  │
            │  2. isTrivial check — пропуск LLM если текст уже чистый          │
            │  3. Snippet placeholder injection (embedded snippets)             │
            │  4. LLMClient.normalize(text, mode, hints) → llama-server HTTP   │
            │     TextMode → system prompt (TextMode.basePrompt + mode-specific)│
            │  5. NormalizationGate.validate() — контракт LLM вывода:          │
            │     empty, refusal, disproportionateLength,                       │
            │     missingProtectedTokens, excessiveEdits, invalidLengthRatio    │
            │  6. Gate pass → LLM text; gate fail → deterministic fallback      │
            │  7. SnippetReinserter.reinsert() — заменить placeholder на content│
            └───────────────────────────────────────────────────────────────────┘
        → PipelineResult (rawTranscript, normalizedText, textMode,
                          normalizationPath, latencies, snippetInfo, ...)
    → SessionManager: processing → inserting
    → TextInserterEngine.insert(normalizedText)  [3-way waterfall]
        1. AXSelectedText (fastest, most compatible)
        2. AXValue + AXSelectedTextRange composition
        3. Clipboard sandwich (save → setString → Cmd+V → restore)
    → SessionManager: inserting → idle
    → AnalyticsService.emit(insertionSucceeded, metadata)
    → HistoryStore.save(result, appContext)
    → PostInsertionMonitor.startMonitoring()     [60s окно, zero-edit rate]
    → BottomBarController / SoundPlayer — feedback
    → AppState.lastResult = result
```

**Нормализация snippets:**
- `standalone` — весь транскрипт = триггер → вставить `content` как есть, 0ms LLM
- `embedded` — триггер внутри фразы → инжект placeholder в LLM промпт → `SnippetReinserter.reinsert()`

**Cancellation:** Esc во время recording/processing → `processingTask?.cancel()` → `PipelineError.cancelled`

## Ключевые абстракции / протоколы

| Протокол | Место | Реализация |
|----------|-------|------------|
| `STTClient` | `Services/STTClient.swift` | `LocalSTTClient` (unix socket) |
| `LLMClient` | `Services/LLMClient.swift` | `LocalLLMClient` (HTTP), `PlaceholderLLMClient` (no-op) |
| `ASRWorkerManaging` | `Services/ASRWorkerManager.swift` | `ASRWorkerManager` |
| `LLMRuntimeManaging` | `Services/LLMRuntimeManager.swift` | `LLMRuntimeManager` |
| `SuperAssetsManaging` | `Services/SuperAssetsManager.swift` | `SuperAssetsManager` |
| `SuperModelDownloading` | `Services/SuperModelDownloadManager.swift` | `SuperModelDownloadManager` |
| `AudioRecording` | `Core/AudioCapture.swift` | `AudioCapture` |
| `TextInserting` | `Core/TextInserter.swift` | `TextInserterEngine` |
| `EventMonitoring` | `Core/ActivationKeyMonitor.swift` | `NSEventMonitoring` |
| `SnippetMatching` | `Core/PipelineEngine.swift` | `SnippetEngine` |
| `AnalyticsEmitting` | `Core/AnalyticsEmitting.swift` | `AnalyticsService` (actor), `NoOpAnalyticsService` |
| `AccessibilityProviding` | `Core/TextInserter.swift` | `SystemAccessibilityProvider` |
| `ClipboardProviding` | `Core/TextInserter.swift` | `SystemClipboardProvider` |
| `WorkspaceProviding` | `Core/AppContextEngine.swift` | `NSWorkspaceProvider` |
| `SoundPlaying` | `Core/SoundManager.swift` | `SystemSoundPlayer`, `MuteSoundPlayer` |
| `PostInsertionMonitoring` | `Core/PostInsertionMonitor.swift` | `PostInsertionMonitor` |

## Concurrency модель

- `@MainActor` — AppState, ActivationKeyMonitor, SessionManager, StatusBarController, BottomBarController, PostInsertionMonitor, ModelManager
- `actor` — AnalyticsService (изолирует запись SwiftData)
- `@unchecked Sendable` + `NSLock` — PipelineEngine, ASRWorkerManager, LocalLLMClient, SnippetEngine, TextInserterEngine (ручная синхронизация для thread-safe доступа к mutable state)
- `async/await` — всё IPC и HTTP; никаких completion handlers
- Swift strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)

## AppContextEngine (TextMode detection)

`Core/AppContextEngine.swift` — определяет `TextMode` по `bundleId` frontmost app:
- hardcoded маппинг 15 приложений (Telegram→chat, Mail→email, Xcode→code, ...)
- пользовательские overrides через `UserDefaults` (`AppModeOverriding` протокол)
- `TextMode` определяет system prompt для LLM нормализации

## LLM Runtime (Говорун Super)

**Lifecycle:**
1. `SuperAssetsManager.check()` — ищет `Helpers/llama-server` (bundle) + `~/.govorun/models/gigachat-gguf.gguf`
2. Если модель не скачана → `SuperModelDownloadManager.download()` — HTTP Range + `.partial.meta` (resume), SHA256 верификация, источник: HF pinned commit
3. `LLMRuntimeManager.start()` — запускает `llama-server` как дочерний процесс, ждёт healthcheck GET /health
4. `LocalLLMClient` — OpenAI-compatible API, `LocalLLMHealthState` actor (failFast / probe / skipProbe паттерн)

**Конфигурация:** temperature=0, max_tokens=128, stop=["\n\n"], endpoint localhost:8080/v1

## Analytics

`AnalyticsService` (actor) пишет в `analytics.store` (отдельный SQLite через SwiftData). Лимит 10 000 событий (FIFO rotation).

`MetricsAggregator` — читает события, считает:
- zero-edit rate (§6.1)
- insertion success rate (§6.3)
- latency percentiles p50/p90/p95 (§6.4)

`PostInsertionMonitor` — после вставки 60 секунд следит за правками (polling 2s + key monitor + app switch). Emits `manualEditDetected` / `undoDetected`.

## Запуск приложения (cold start)

```
applicationDidFinishLaunching
    ↓
AppState.init() — wire all services
    ↓
if onboardingCompleted:
    AppState.start()
        ├── superAssetsManager.check() → superAssetsState
        ├── if superMode: llmRuntimeManager.start()
        ├── workerManager.start() → Python setup → LOADING → LOADED → READY
        └── isReady = true
else:
    OnboardingWindowController (6 шагов: welcome → mic → accessibility → model → superModel → tryIt)
    onComplete → AppState.start()
```

Worker cold start: `ASRWorkerManager` запускает `python3 server.py` через embedded Python.framework, парсит stdout (`LOADING`, `LOADED`, `READY`, `DOWNLOADING XX%`), управляет restart (до N попыток).

## CI/CD

- `/.github/workflows/tests.yml` — xcodebuild test + pytest
- `/.github/workflows/release.yml` — xcodegen → тесты → DMG → Sparkle EdDSA → GitHub Release → appcast.xml
- `appcast.xml` — Sparkle appcast (EdDSA подпись)
- `project.yml` — XcodeGen конфиг (не xcodeproj в git)
