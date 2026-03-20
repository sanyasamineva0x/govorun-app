# Говорун

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн.
Зажал клавишу → сказал → отпустил → чистый текст в активном поле.

## Стек

- Swift 5.10+, macOS 14.0+ (Sonoma), Apple Silicon (M1+)
- SwiftUI + AppKit (NSStatusItem, NSPanel, NSEvent, AXUIElement)
- AVAudioEngine (микрофон, metering)
- Python 3.13 worker (unix socket IPC, embedded Python.framework)
- onnx-asr (GigaAM-v3 e2e_rnnt, ONNX Runtime)
- Silero VAD (нарезка длинного аудио)
- Sparkle 2 (автообновление с EdDSA подписью)
- SwiftData (история, словарь, сниппеты)
- XCTest (739 тестов)

## Архитектура

```
Swift App (menu bar)                    Python Worker
┌──────────────────────┐               ┌──────────────────────┐
│ Activation Key Monitor│               │ onnx-asr             │
│ AudioCapture (16kHz) │──── unix ────▶│ GigaAM-v3 e2e_rnnt   │
│ PipelineEngine       │    socket     │ Silero VAD (нарезка) │
│ DeterministicNorm    │◀─────────────│                      │
│ DictionaryStore      │               └──────────────────────┘
│ SnippetEngine        │
│ NumberNormalizer     │
│ AppContextEngine     │
│ TextInserter (AX)    │
│ UpdaterService       │
│ BottomBar UI         │
│ Settings / History   │
└──────────────────────┘
```

Слои:
- Core/ НЕ импортирует SwiftUI или AppKit (чистый Swift)
- Services/ НЕ импортирует AppKit
- Models/ — чистые value types
- worker/ — Python, общается ТОЛЬКО через unix socket

## Pipeline

```
Activation key down → AudioCapture (16kHz PCM mono) → Activation key up →
→ сохранить WAV в tmp →
→ LocalSTTClient → unix socket → Python worker →
→ Silero VAD → нарезка → GigaAM e2e_rnnt → склейка →
→ текст с пунктуацией ←
→ DictionaryStore.applyReplacements() →
→ [Snippet standalone?] → content as-is
→ [Snippet embedded?] → mechanicalFallback
→ DeterministicNormalizer (филлеры, капитализация, NumberNormalizer) →
→ TextInserter (AX selectedText → composition → clipboard)
```

## IPC протокол (JSON через unix socket)

Socket path: `~/.govorun/worker.sock`

```
Запрос ASR:    {"wav_path": "/tmp/govorun_xxx.wav"}
Ответ ASR:     {"text": "распознанный текст"}
Ошибка:        {"error": "oom|file_not_found|internal", "message": "..."}
Ping:          {"cmd": "ping"} → {"status": "ok", "version": "1"}
```

Один request за connection. Worker stateless.

Детали:
- recv loop (не один `recv(4096)`) — читаем до EOF
- Client sends `shutdown(SHUT_WR)` после отправки request
- `DOWNLOADING N%` в stdout — прогресс скачивания модели (ASRWorkerManager парсит)
- Path traversal protection: `realpath()` + проверка allowed prefixes

## Конвенции

- Язык кода: Swift + Python. Комментарии — минимальные, на русском
- Коммиты на русском: `feat: добавить X`, `fix: исправить Y`
- TDD: тест (red) → код (green) → рефактор
- Все сервисы через протоколы (STTClient, LLMClient, UpdateChecking, TextInserting)
- Моки в тестах, никогда реальный Python worker или модели
- Ошибки типизированы: `enum XxxError: Error { ... }`
- async/await, не completion handlers
- @MainActor только для UI-кода
- Нет force unwrap (!) в production коде
- Zero API credentials — всё локально
- AnalyticsEvent в отдельном store (analytics.store)
- launchAtLogin через SMAppService
- soundEnabled читается из UserDefaults на каждый play()

## Git-процесс

- Ветка `feat/<name>` или `fix/<name>` → PR → squash merge
- После мержа: `git checkout main && git pull && git branch -d <ветка>`
- Не коммитить в main напрямую
- Одна живая ветка за раз
- Auto-delete branch on merge

## Релиз-процесс

При каждом новом релизе:

1. Bump `MARKETING_VERSION` в `project.yml`
2. `xcodegen generate` + fix objectVersion 56
3. `bash scripts/build-unsigned-dmg.sh`
4. Подписать DMG: `sign_update build/Govorun.dmg` (Sparkle EdDSA)
5. `gh release create vX.Y.Z build/Govorun.dmg`
6. Добавить `<item>` в `appcast.xml` с edSignature и length из п.4
7. Коммит + push appcast.xml
8. Обновить Cask: version + sha256 в `homebrew-govorun/Casks/govorun.rb`

`sign_update` находится в DerivedData:
```
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*"
```

## Структура

```
Govorun/
├── GovorunApp.swift
├── Info.plist
├── Govorun.entitlements
├── App/                        # UI + event handling
│   ├── AppState.swift          # Composition root
│   ├── StatusBarController.swift
│   ├── BottomBarWindow.swift
│   ├── BottomBarView.swift
│   ├── SettingsWindowController.swift
│   ├── OnboardingWindowController.swift
│   ├── AXTextInserter.swift
│   ├── SystemSoundPlayer.swift
│   ├── NSEventMonitoring.swift
│   ├── NSWorkspaceProvider.swift
│   └── PostInsertionProviders.swift
├── Core/                       # Бизнес-логика (без UI)
│   ├── ActivationKeyMonitor.swift
│   ├── SessionManager.swift
│   ├── PipelineEngine.swift
│   ├── AudioCapture.swift
│   ├── TextInserter.swift
│   ├── AppContextEngine.swift
│   ├── SnippetEngine.swift
│   ├── SoundManager.swift
│   ├── ErrorMessages.swift
│   ├── ErrorClassifier.swift
│   ├── AnalyticsEmitting.swift
│   ├── PostInsertionMonitor.swift
│   ├── NumberNormalizer.swift
│   └── NetworkMonitor.swift
├── Services/                   # IPC, внешние сервисы
│   ├── ASRWorkerManager.swift
│   ├── LocalSTTClient.swift
│   ├── ModelManager.swift
│   ├── STTClient.swift
│   ├── LLMClient.swift
│   ├── UpdaterService.swift   # Sparkle 2 автообновление (UpdateChecking протокол)
│   └── AnalyticsService.swift
├── Models/                     # Value types
│   ├── ActivationKey.swift    # Enum: modifier/keyCode/combo + Codable + displayName
│   ├── TextMode.swift
│   ├── DictionaryEntry.swift
│   ├── Snippet.swift
│   ├── HistoryItem.swift
│   └── AnalyticsEvent.swift
├── Storage/                    # Persistence
│   ├── DictionaryStore.swift
│   ├── SnippetStore.swift
│   ├── HistoryStore.swift
│   ├── SettingsStore.swift
│   ├── AudioHistoryStorage.swift
│   └── MetricsAggregator.swift
├── Views/                      # SwiftUI
│   ├── KeyRecorderView.swift  # UI recorder для выбора клавиши активации
│   ├── SettingsView.swift
│   ├── SettingsTheme.swift
│   ├── HistoryView.swift
│   ├── DictionaryView.swift
│   ├── SnippetListView.swift
│   ├── OnboardingView.swift
│   └── AppModeSettingsView.swift
└── Resources/
    ├── Assets.xcassets
    └── Sounds/
GovorunTests/                   # 739 тестов
worker/                         # Python ASR worker
├── server.py
├── requirements.txt
├── setup.sh
├── test_server.py
└── VERSION
scripts/                        # Сборка и дистрибуция
Frameworks/
└── Python.framework/           # Embedded Python 3.13
appcast.xml                     # Sparkle feed (обновлять при каждом релизе)
```

## Команды

```bash
# Xcode
⌘R              # Запуск
⌘U              # Тесты
⌘⇧K            # Clean Build

# CLI
xcodebuild test -scheme Govorun -destination 'platform=macOS'

# Python worker
cd worker && python3 -m pytest test_server.py -v

# Подписать DMG для Sparkle
$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*") build/Govorun.dmg
```

## Модели

| Модель | Размер | RAM | Назначение |
|--------|--------|-----|------------|
| GigaAM-v3 e2e_rnnt (3 ONNX) | ~892 MB | ~1.5 GB | ASR |
| Silero VAD (ONNX) | ~2 MB | ~50 MB | Нарезка аудио |

Кэш: `~/.cache/huggingface/hub/`
