# Архитектура Говоруна

## Общая схема

```
Swift App (menu bar)                    Python Worker
┌──────────────────────┐               ┌──────────────────────┐
│ Activation Key Monitor│               │ onnx-asr             │
│ AudioCapture (16kHz) │──── unix ────▶│ GigaAM-v3 e2e_rnnt   │
│ PipelineEngine       │    socket     │ Silero VAD (нарезка) │
│ NormalizationPipeline│◀─────────────│                      │
│ LocalLLMClient       │               └──────────────────────┘
│ SuperAssetsManager   │
│ DictionaryStore      │               Local LLM (Говорун Super)
│ SnippetEngine        │               ┌──────────────────────┐
│ NumberNormalizer     │── HTTP ──────▶│ llama-server          │
│ AppContextEngine     │  localhost    │ GigaChat3.1 Q4_K_M   │
│ TextInserter (AX)    │◀─────────────│ OpenAI-compatible API │
│ BottomBar UI         │               └──────────────────────┘
│ Settings / History   │
└──────────────────────┘
```

## Структура каталогов

```
Govorun/
├── GovorunApp.swift
├── Info.plist                     # CFBundleVersion, Sparkle config
├── Govorun.entitlements
├── App/
│   ├── AppState.swift             # Composition root, wiring, pending settings
│   ├── StatusBarController.swift  # Menu bar icon
│   ├── BottomBarWindow.swift      # NSPanel pill
│   ├── BottomBarView.swift        # SwiftUI pill, OrganicPillShape, glass morphing
│   ├── SettingsWindowController.swift
│   ├── OnboardingWindowController.swift
│   ├── AXTextInserter.swift
│   ├── SystemSoundPlayer.swift
│   ├── NSEventMonitoring.swift    # CGEventTap + fallback
│   └── PostInsertionProviders.swift
├── Core/
│   ├── ActivationKeyMonitor.swift # modifier/keyCode/combo + PTT/toggle
│   ├── SessionManager.swift
│   ├── PipelineEngine.swift       # Orchestrator: ASR → normalize → insert
│   ├── NormalizationPipeline.swift # DeterministicNormalizer + LLMResponseGuard + isTrivial + preflight/postflight
│   ├── AudioCapture.swift
│   ├── TextInserter.swift         # 3-strategy waterfall (AX → composition → clipboard)
│   ├── AppContextEngine.swift
│   ├── SnippetEngine.swift
│   ├── SoundManager.swift
│   ├── ErrorMessages.swift
│   ├── ErrorClassifier.swift
│   ├── AnalyticsEmitting.swift
│   ├── PostInsertionMonitor.swift
│   ├── NumberNormalizer.swift
│   └── NetworkMonitor.swift
├── Services/
│   ├── ASRWorkerManager.swift     # Python worker lifecycle
│   ├── LocalSTTClient.swift       # Unix socket → worker
│   ├── ModelManager.swift         # GigaAM model discovery
│   ├── STTClient.swift
│   ├── LLMClient.swift            # LocalLLMClient + config + PlaceholderLLMClient
│   ├── LocalLLMClient.swift       # HTTP → llama-server (OpenAI API)
│   ├── LLMRuntimeManager.swift    # llama-server process lifecycle
│   ├── SuperAssetsManager.swift   # Discovery llama-server + GGUF, readiness state
│   ├── SuperModelDownloadManager.swift # Скачивание GGUF с HF, resume, SHA256
│   ├── UpdaterService.swift       # Sparkle 2
│   └── AnalyticsService.swift
├── Models/
│   ├── ActivationKey.swift
│   ├── RecordingMode.swift        # pushToTalk / toggle
│   ├── TextMode.swift             # universal/chat/email/document/note/code + prompt generation
│   ├── ProductMode.swift          # standard / superMode
│   ├── SuperModelDownloadSpec.swift  # Spec для скачивания (url, SHA256, size)
│   ├── SuperModelDownloadState.swift # State machine скачивания + ошибки
│   ├── SuperModelCatalog.swift    # Каталог моделей (pinned HF commit)
│   ├── DictionaryEntry.swift
│   ├── Snippet.swift
│   ├── HistoryItem.swift
│   └── AnalyticsEvent.swift
├── Storage/
│   ├── SettingsStore.swift        # UserDefaults, all settings
│   ├── DictionaryStore.swift
│   ├── SnippetStore.swift
│   ├── HistoryStore.swift
│   ├── AudioHistoryStorage.swift
│   └── MetricsAggregator.swift
├── Views/
│   ├── KeyRecorderView.swift
│   ├── SettingsView.swift         # ProductModeCard, LLM settings
│   ├── SettingsTheme.swift
│   ├── HistoryView.swift
│   ├── DictionaryView.swift
│   ├── SnippetListView.swift
│   ├── OnboardingView.swift
│   └── AppModeSettingsView.swift
└── Resources/
    ├── Assets.xcassets
    └── Sounds/
GovorunTests/                      # 986 тестов
worker/                            # Python ASR worker
├── server.py
├── requirements.txt
├── setup.sh
├── test_server.py
└── VERSION
scripts/
├── build-unsigned-dmg.sh          # Framework + worker + wheels + llama-server → DMG
├── build-llama-server.sh          # Static arm64 llama-server (cmake, pinned tag)
├── build-dmg.sh                   # Signed + notarized
├── fetch-python-framework.sh
├── download-wheels.sh
├── run-gigachat-llm.sh            # Dev: запуск llama-server (Helpers/ → PATH → build-temp)
├── benchmark-llm-normalization.py # LLM/full-pipeline benchmark
└── benchmark-full-pipeline-helper.swift
benchmarks/
├── llm-normalization-seed.jsonl   # 36 samples
├── prompts/                       # Snapshot промптов
├── reports/                       # Результаты бенчмарков
└── README.md
```

## IPC протокол (unix socket)

Socket path: `~/.govorun/worker.sock`

```
Запрос ASR:    {"wav_path": "/tmp/govorun_xxx.wav"}
Ответ ASR:     {"text": "распознанный текст"}
Ошибка:        {"error": "oom|file_not_found|internal", "message": "..."}
Ping:          {"cmd": "ping"} → {"status": "ok", "version": "1"}
```

Один request за connection. Worker stateless. Таймаут: 300 секунд.

## Релиз-процесс

**Автоматический (CI):**

1. Bump `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` в `project.yml`
2. Коммит + push
3. `git tag v0.X.Y && git push --tags`
4. `release.yml`: xcodegen → llama-server (cache/build + validate) → тесты → DMG → Sparkle EdDSA → GitHub Release → appcast.xml → Homebrew Cask

`CURRENT_PROJECT_VERSION` = patch segment (для `v0.1.11` → 11).

**Secrets:** `SPARKLE_PRIVATE_KEY`, `RELEASE_PAT`, `HOMEBREW_APP_ID` (3173509), `HOMEBREW_APP_PRIVATE_KEY`.

**Ручной:** bump project.yml → xcodegen → build-unsigned-dmg.sh → sign_update → gh release create → appcast.xml → homebrew cask.
