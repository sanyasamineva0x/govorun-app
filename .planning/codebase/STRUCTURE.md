# Структура директорий Говоруна

## Верхний уровень

```
govorun-app/
├── Govorun/                    # Swift исходники (64 .swift файла)
├── GovorunTests/               # Тесты (36 .swift файлов, ~986 тестов)
├── worker/                     # Python ASR worker (2 .py файла)
├── Frameworks/                 # Python.framework (в .gitignore, скачивается)
├── Helpers/                    # llama-server binary (в .gitignore, собирается)
├── scripts/                    # Build и setup скрипты (8 файлов)
├── benchmarks/                 # Бенчмарки и промпты (10 файлов)
├── docs/                       # Спецификации и дока (7 файлов)
├── build/                      # Артефакты сборки (в .gitignore)
├── .planning/                  # Планирование (этот каталог)
├── .claude/                    # Claude settings + skills
├── .github/workflows/          # CI: tests.yml, release.yml
├── project.yml                 # XcodeGen конфиг (источник правды для xcodeproj)
├── Govorun.xcodeproj/          # Генерируется XcodeGen, не в git
├── Govorun.xctestplan          # Test plan
├── ExportOptions.plist         # Xcode archive export
├── appcast.xml                 # Sparkle appcast
├── AGENTS.md                   # Правила для AI-агентов
├── CLAUDE.md                   # Инструкции для Claude
├── .swiftformat                # SwiftFormat конфиг
└── .gitignore
```

## Govorun/ — Swift исходники

### Корень

| Файл | Назначение |
|------|------------|
| `Govorun/GovorunApp.swift` | Entry point (`@main`), `AppModelContainer`, `AppDelegate` |
| `Govorun/Info.plist` | Bundle metadata, LSUIElement=true, Sparkle config |
| `Govorun/Govorun.entitlements` | com.apple.security.automation.apple-events и др. |

### App/ (11 файлов) — UI shell и системные интеграции

```
Govorun/App/
├── AppState.swift              # Composition root (~1400 строк). Все сервисы, wiring,
│                               # pending settings, @Published состояния
├── StatusBarController.swift   # NSStatusItem, меню, обновление icon/title
├── BottomBarWindow.swift       # NSPanel pill: BottomBarState enum, BrandColors,
│                               # BottomBarMetrics, BottomBarController (@MainActor)
├── BottomBarView.swift         # SwiftUI pill: PillMotion, OrganicPillShape,
│                               # Liquid Glass (macOS 26+) + legacy fallback
├── NSEventMonitoring.swift     # EventMonitoring impl: CGEventTap + NSEvent fallback,
│                               # ActivationEventTap
├── AXTextInserter.swift        # AXFocusedElement, SystemAccessibilityProvider,
│                               # SystemClipboardProvider
├── PostInsertionProviders.swift # SystemFocusedTextReader, SystemFrontmostAppProvider,
│                               # SystemGlobalKeyMonitorProvider
├── NSWorkspaceProvider.swift   # WorkspaceProviding impl через NSWorkspace
├── SettingsWindowController.swift  # NSWindowController для Settings
├── OnboardingWindowController.swift # NSWindowController для онбординга
└── SystemSoundPlayer.swift     # SoundPlaying impl через NSSound (recording_started/finished/error.aiff)
```

### Core/ (16 файлов) — бизнес-логика, чистый Swift

```
Govorun/Core/
├── PipelineEngine.swift        # Оркестратор ASR→нормализация→вставка.
│                               # PipelineResult, PipelineError, SnippetMatch,
│                               # SnippetReinserter, SnippetMatchKind
├── NormalizationPipeline.swift # DeterministicNormalizer: филлеры, числа, капитализация,
│                               # canonical surface forms. NormalizationHints
├── NumberNormalizer.swift      # Числа словами → цифры (61 KB, самый большой файл Core/)
├── NormalizationGate.swift     # LLMOutputContract, NormalizationGateFailureReason,
│                               # валидация LLM вывода (6 check типов)
├── ActivationKeyMonitor.swift  # @MainActor монитор клавиши: PTT / toggle, combo,
│                               # EventMonitoring протокол, ActivationKeyConstants
├── AudioCapture.swift          # AVFoundation 16kHz PCM mono. AudioRecording протокол,
│                               # AudioCaptureDelegate, AudioCaptureError
├── TextInserter.swift          # 3-way waterfall: AXSelectedText → AXValue composition
│                               # → clipboard. TextInserterEngine, TextInserting,
│                               # AccessibilityProviding, ClipboardProviding
├── SessionManager.swift        # @MainActor FSM: idle→recording→processing→inserting→idle
│                               # SessionState, SessionManagerDelegate
├── AppContextEngine.swift      # AppContext, bundleId→TextMode маппинг (15 приложений),
│                               # WorkspaceProviding, AppModeOverriding
├── SnippetEngine.swift         # SnippetMatching, SnippetRecord, exact/fuzzy/embedded match,
│                               # Levenshtein distance
├── PostInsertionMonitor.swift  # 60s мониторинг правок: polling 2s + key monitor + app switch.
│                               # FocusedTextReading, FrontmostAppProviding
├── ErrorClassifier.swift       # Классификация Error → AnalyticsErrorType
├── ErrorMessages.swift         # Локализованные сообщения ошибок для UI
├── SoundManager.swift          # SoundPlaying протокол, SoundEvent, MuteSoundPlayer
├── AnalyticsEmitting.swift     # AnalyticsEmitting протокол, NoOpAnalyticsService
└── NetworkMonitor.swift        # NWPathMonitor обёртка, @Published isConnected
```

### Services/ (11 файлов) — внешние интеграции

```
Govorun/Services/
├── ASRWorkerManager.swift      # Python worker lifecycle: запуск Process,
│                               # stdout parsing (LOADING/LOADED/READY/DOWNLOADING),
│                               # auto-restart, WorkerState, WorkerError,
│                               # ASRWorkerManaging протокол
├── LocalSTTClient.swift        # STTClient impl: WAV → unix socket → JSON response
├── STTClient.swift             # STTClient протокол, STTResult, STTError
├── LLMClient.swift             # LLMClient протокол, LLMError, LocalLLMConfiguration
├── LocalLLMClient.swift        # HTTP → llama-server OpenAI API. LocalLLMHealthState actor
│                               # (failFast/probe/skipProbe). LocalLLMRuntimeConfiguration
├── LLMRuntimeManager.swift     # llama-server process lifecycle: запуск, healthcheck,
│                               # LLMRuntimeState, LLMRuntimeError, LLMRuntimeManaging
├── SuperAssetsManager.swift    # Проверка наличия llama-server binary + GGUF.
│                               # SuperAssetsState, FileChecking, SuperAssetsManaging
├── SuperModelDownloadManager.swift # Скачивание GGUF с HF: HTTP Range + .partial.meta resume,
│                               # SHA256 верификация. SuperModelDownloading протокол,
│                               # PartialDownloadMeta
├── ModelManager.swift          # @MainActor. Проверка GigaAM ONNX в HF cache.
│                               # ModelDownloadState, expectedFiles (3 ONNX)
├── AnalyticsService.swift      # actor. SwiftData запись в analytics.store.
│                               # FIFO rotation (max 10 000 событий)
└── UpdaterService.swift        # Sparkle 2 SPUUpdater обёртка. UpdateChecking протокол
```

### Models/ (11 файлов) — value types и SwiftData models

```
Govorun/Models/
├── TextMode.swift              # enum: chat/email/document/note/code/universal.
│                               # TextMode.basePrompt() — system prompt генерация (14 KB)
├── ActivationKey.swift         # enum: modifier keys, keyCode, combos. Сериализация
├── RecordingMode.swift         # enum: pushToTalk / toggle
├── ProductMode.swift           # enum: standard / superMode. usesLLM computed var
├── SuperModelCatalog.swift     # Каталог GGUF (pinned HF commit, SHA256, 6.4 GB)
├── SuperModelDownloadSpec.swift # Struct: url, destination, SHA256, expectedSize
├── SuperModelDownloadState.swift # enum state machine + error cases для скачивания
├── AnalyticsEvent.swift        # @Model SwiftData. AnalyticsEventName, InsertionStrategy,
│                               # AnalyticsErrorType, AnalyticsMetadataKey
├── DictionaryEntry.swift       # @Model SwiftData: word + alternatives[]
├── Snippet.swift               # @Model SwiftData: trigger, content, matchMode (exact/fuzzy)
└── HistoryItem.swift           # @Model SwiftData: sessionId, rawTranscript, normalizedText,
│                               # textMode, latencies, wordCount, insertionStrategy
```

### Storage/ (6 файлов) — SwiftData CRUD

```
Govorun/Storage/
├── SettingsStore.swift         # UserDefaults обёртка. productMode, activationKey,
│                               # recordingMode, soundEnabled, llm config, onboardingCompleted
├── DictionaryStore.swift       # CRUD для DictionaryEntry. merge на дубликатах
├── SnippetStore.swift          # CRUD для Snippet. seedDefaultsIfNeeded()
├── HistoryStore.swift          # Append-only, max 100 записей (FIFO)
├── AudioHistoryStorage.swift   # Сохранение WAV файлов (~/.govorun/audio/)
└── MetricsAggregator.swift     # Читает AnalyticsEvent, считает zero-edit rate,
│                               # insertion success rate, latency percentiles p50/p90/p95
```

### Views/ (8 файлов) — SwiftUI

```
Govorun/Views/
├── SettingsView.swift          # Главный экран настроек. SettingsSidebar + 5 секций.
│                               # GeneralSettingsContent, SettingsSection enum (26 KB)
├── OnboardingView.swift        # 6-шаговый онбординг: OnboardingStep enum,
│                               # прогресс-бар, mic/AX permissions, model download (23 KB)
├── AppModeSettingsView.swift   # Выбор ProductMode + per-app TextMode overrides
├── KeyRecorderView.swift       # Запись кастомной клавиши активации
├── DictionaryView.swift        # CRUD UI для личного словаря
├── SnippetListView.swift       # CRUD UI для сниппетов
├── HistoryView.swift           # История вставок с latency и app info
└── SettingsTheme.swift         # Design tokens: цвета (cottonCandy, skyAqua, oceanMist,
│                               # petalFrost, alabasterGrey), fonts, spacing
```

### Resources/

```
Govorun/Resources/
├── Assets.xcassets/AppIcon.appiconset/  # PNG иконки (16/32/64/128/256/512/1024px)
└── Sounds/
    ├── recording_started.aiff
    ├── recording_finished.aiff
    └── error.aiff
```

## GovorunTests/ (36 файлов)

Все тесты в одном flat каталоге. Именование: `{SubjectName}Tests.swift`.

| Файл | Что тестирует |
|------|---------------|
| `PipelineEngineTests.swift` | Крупнейший тест-файл (53 KB). Полный pipeline |
| `NumberNormalizerTests.swift` | Числа словами (47 KB) |
| `ToggleRecoveryTests.swift` | Toggle режим записи, recovery (34 KB) |
| `IntegrationTests.swift` | End-to-end с моками (28 KB) |
| `ASRWorkerManagerTests.swift` | Worker lifecycle (28 KB) |
| `ColdStartUITests.swift` | Cold start / onboarding UI (27 KB) |
| `SuperModelDownloadManagerTests.swift` | Download, resume, SHA256 (16 KB) |
| `LocalLLMClientTests.swift` | HTTP mock, healthcheck (15 KB) |
| `NormalizationGateTests.swift` | Gate validation (11 KB) |
| `AppContextEngineTests.swift` | TextMode detection (10 KB) |
| `LLMRuntimeManagerTests.swift` | llama-server lifecycle (9 KB) |
| `TextInserterTests.swift` | 3-way waterfall (21 KB) |
| `SnippetEngineTests.swift` | Exact/fuzzy/embedded (20 KB) |
| `ActivationKeyMonitorTests.swift` | PTT/toggle/combo (20 KB) |
| `NormalizationPipelineTests.swift` | Deterministic pipeline (5 KB) |
| `TestHelpers.swift` | Общие моки и хелперы |
| ... | (другие unit тесты по компонентам) |

## worker/ (Python)

```
worker/
├── server.py           # Unix socket сервер. GigaAM-v3 + Silero VAD через onnx-asr.
│                       # Протокол: {"wav_path":...} → {"text":...}
│                       # stdout: LOADING/LOADED/READY/DOWNLOADING XX%
├── test_server.py      # pytest тесты (20 KB)
├── requirements.txt    # onnx-asr, huggingface-hub, numpy и др.
├── setup.sh            # pip install в venv (bundled wheels)
├── VERSION             # Версия worker (парсится ASRWorkerManager для update check)
└── wheels/             # Bundled pip wheels (в .gitignore, ~124 MB, скачиваются)
```

## scripts/ (8 файлов)

```
scripts/
├── fetch-python-framework.sh       # Скачать Python.framework 3.13 (~63 MB)
├── download-wheels.sh              # Скачать pip wheels (~124 MB)
├── build-llama-server.sh           # Собрать llama-server arm64 статически (~5 мин)
├── run-gigachat-llm.sh             # Запустить llama-server вручную для отладки
├── build-unsigned-dmg.sh           # Основной build-скрипт: xcodegen→xcodebuild→DMG
├── build-dmg.sh                    # Signed DMG (для релиза)
├── benchmark-llm-normalization.py  # Python бенчмарк нормализации (34 KB)
└── benchmark-full-pipeline-helper.swift  # Swift хелпер для pipeline бенчмарков
```

## docs/ (7 файлов)

```
docs/
├── architecture.md             # Исходная архитектурная документация (7 KB)
├── llm-normalization-roadmap.md # LLM нормализация: roadmap, метрики, spec (32 KB)
├── canonical-style-spec.md     # Canonical style guide (2 KB)
├── liquid-pill-spec.md         # Liquid Glass pill spec (8 KB)
├── recording-mode-spec.md      # PTT/toggle spec (7 KB)
├── plans/                      # (пусто)
└── superpowers/                # Браузерные прототипы (HTML mockups)
```

## benchmarks/ (10 файлов)

```
benchmarks/
├── README.md
├── llm-normalization-seed.jsonl      # Тестовые примеры для нормализации
├── prompts/                          # 3 версии system prompt
│   ├── 2026-03-27-system-prompt-production-head.txt
│   ├── 2026-03-27-system-prompt-production-product-canon.txt
│   └── 2026-03-27-system-prompt-v3b.txt
└── reports/                          # 6 отчётов по датам и конфигурациям
    ├── 2026-03-26-gigachat3.1-m1-16gb.md
    ├── 2026-03-27-full-pipeline-*.md (4 файла)
    └── 2026-03-27-prompt-v3b-m1-16gb.md
```

## Конвенции именования

**Swift файлы:**
- `{Name}Service.swift` — внешняя интеграция с протоколом (`AnalyticsService`, `UpdaterService`)
- `{Name}Manager.swift` — lifecycle management (`ASRWorkerManager`, `LLMRuntimeManager`, `SuperAssetsManager`, `SuperModelDownloadManager`, `ModelManager`)
- `{Name}Store.swift` — SwiftData persistence (`SettingsStore`, `DictionaryStore`, `HistoryStore`, `SnippetStore`)
- `{Name}Engine.swift` — stateful бизнес-логика (`PipelineEngine`, `SnippetEngine`, `AppContextEngine`)
- `{Name}Monitor.swift` — наблюдение за внешними событиями (`ActivationKeyMonitor`, `PostInsertionMonitor`, `NetworkMonitor`)
- `{Name}View.swift` — SwiftUI view
- `{Name}Controller.swift` — AppKit controller (`StatusBarController`, `BottomBarController`, `SettingsWindowController`)
- `{Name}Tests.swift` — XCTest file

**Типизированные ошибки:** `enum {Name}Error: Error, LocalizedError` в том же файле где тип.

**Протоколы:** суффикс `*ing` (`SnippetMatching`, `TextInserting`, `AudioRecording`) или `*Providing` / `*Managing` / `*Emitting` / `*Downloading`.

**SwiftData models:** `@Model final class {Name}` (не struct) — `DictionaryEntry`, `Snippet`, `HistoryItem`, `AnalyticsEvent`.

**State machines:** `enum {Name}State` рядом с классом-владельцем — `SessionState`, `WorkerState`, `LLMRuntimeState`, `SuperAssetsState`, `SuperModelDownloadState`, `BottomBarState`.

## Файловая система приложения (runtime)

```
~/.govorun/
├── worker.sock             # Unix socket (создаётся Python worker'ом)
├── models/
│   └── gigachat-gguf.gguf  # GigaChat 3.1 GGUF (~6.4 GB, скачивается автоматически)
│   └── gigachat-gguf.gguf.partial.meta  # Resume metadata (если скачивание не завершено)
└── audio/                  # WAV история (опционально, если saveAudioHistory=true)

~/.cache/huggingface/hub/models--istupakov--gigaam-v3-onnx/
└── snapshots/{hash}/       # 3 ONNX файла GigaAM-v3 (~892 MB, скачивает Python worker)
    ├── v3_e2e_rnnt_encoder.onnx
    ├── v3_e2e_rnnt_decoder.onnx
    └── v3_e2e_rnnt_joint.onnx

~/Library/Application Support/com.govorun.app/
├── default.store           # SwiftData: DictionaryEntry, Snippet, HistoryItem
└── analytics.store         # SwiftData: AnalyticsEvent (max 10 000)
```

## Ключевые пути в коде

| Что найти | Где |
|-----------|-----|
| Точка входа | `Govorun/GovorunApp.swift` |
| Composition root | `Govorun/App/AppState.swift` |
| Pipeline оркестратор | `Govorun/Core/PipelineEngine.swift` |
| Deterministic нормализация | `Govorun/Core/NormalizationPipeline.swift` |
| Числа словами | `Govorun/Core/NumberNormalizer.swift` |
| LLM gate | `Govorun/Core/NormalizationGate.swift` |
| System prompt | `Govorun/Models/TextMode.swift` → `TextMode.basePrompt()` |
| Клавиша активации | `Govorun/Core/ActivationKeyMonitor.swift` |
| Python worker | `worker/server.py` |
| Worker lifecycle | `Govorun/Services/ASRWorkerManager.swift` |
| Unix socket IPC | `Govorun/Services/LocalSTTClient.swift` |
| llama-server lifecycle | `Govorun/Services/LLMRuntimeManager.swift` |
| LLM HTTP client | `Govorun/Services/LocalLLMClient.swift` |
| GGUF download | `Govorun/Services/SuperModelDownloadManager.swift` |
| GGUF catalog | `Govorun/Models/SuperModelCatalog.swift` |
| Text insertion | `Govorun/Core/TextInserter.swift` |
| AX real impl | `Govorun/App/AXTextInserter.swift` |
| Pill UI | `Govorun/App/BottomBarView.swift` + `BottomBarWindow.swift` |
| Settings | `Govorun/Storage/SettingsStore.swift` |
| Analytics | `Govorun/Services/AnalyticsService.swift` |
| Metrics | `Govorun/Storage/MetricsAggregator.swift` |
| XcodeGen конфиг | `project.yml` |
