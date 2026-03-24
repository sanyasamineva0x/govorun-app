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
- XCTest (799 тестов)

## Сборка и запуск тестовой версии

**ВАЖНО: приложение не запускается через ⌘R в Xcode без подготовки.**

Для запуска нужны Python.framework и wheels — они в .gitignore и не в репо.

### Первая сборка (после клонирования)

```bash
# 1. Скачать Python.framework (63 МБ, один раз)
bash scripts/fetch-python-framework.sh

# 2. Скачать wheels для офлайн pip install (124 МБ, один раз)
bash scripts/download-wheels.sh

# 3. Сгенерировать Xcode проект
xcodegen generate

# 4. Теперь можно ⌘R в Xcode или собрать DMG
```

### Собрать DMG и запустить

```bash
# Собрать DMG (включает Python.framework + wheels + worker)
bash scripts/build-unsigned-dmg.sh

# Установить и запустить
pkill -f Govorun 2>/dev/null; sleep 1
rm -rf /Applications/Govorun.app
hdiutil attach build/Govorun.dmg -nobrowse
MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}')
cp -R "$MOUNT/Govorun.app" /Applications/
hdiutil detach "$MOUNT" 2>/dev/null
xattr -cr /Applications/Govorun.app
open /Applications/Govorun.app
```

### Однострочник (rebuild + install + launch)

```bash
pkill -f Govorun 2>/dev/null; sleep 1; bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)' && rm -rf /Applications/Govorun.app && hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null && MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}') && cp -R "$MOUNT/Govorun.app" /Applications/ && hdiutil detach "$MOUNT" 2>/dev/null && xattr -cr /Applications/Govorun.app && open /Applications/Govorun.app
```

### После переустановки — Accessibility

macOS сбрасывает Accessibility permission при каждой переустановке (code signature меняется).
Если текст не вставляется напрямую:

1. Закрыть Говоруна
2. Системные настройки → Конфиденциальность → Универсальный доступ
3. Удалить Говоруна из списка (−)
4. Запустить Говоруна
5. Включить тогл

### Почему не работает ⌘R в Xcode

`build-unsigned-dmg.sh` вручную копирует Python.framework, worker файлы и wheels в app bundle.
Xcode Copy Files phase может их не скопировать (зависит от objectVersion pbxproj).
**DMG — единственный надёжный способ тестирования.**

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

Один request за connection. Worker stateless. Таймаут: 300 секунд (фиксированный).

## Конвенции

- Язык кода: Swift + Python. Комментарии — минимальные, на русском
- Коммиты на русском: `feat: добавить X`, `fix: исправить Y`
- **Нет Co-Authored-By** — публичный репо, без признаков AI
- TDD: тест (red) → код (green) → рефактор
- Все сервисы через протоколы (STTClient, LLMClient, UpdateChecking, TextInserting)
- Моки в тестах, никогда реальный Python worker или модели
- Ошибки типизированы: `enum XxxError: Error, LocalizedError { ... }`
- async/await, не completion handlers
- @MainActor только для UI-кода
- Нет force unwrap (!) в production коде
- Zero API credentials — всё локально
- AnalyticsEvent в отдельном store (analytics.store)
- Liquid Glass API за `#if compiler(>=6.2)` + `#available(macOS 26, *)`

## Git-процесс

- Ветка `feat/<name>` или `fix/<name>` → PR → squash merge
- После мержа: `git checkout main && git pull && git branch -d <ветка>`
- Не коммитить в main напрямую
- Одна живая ветка за раз
- Auto-delete branch on merge

## Релиз-процесс

**Автоматический (CI):**

1. Bump `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` в `project.yml`
2. Коммит + push
3. `git tag v0.X.Y && git push --tags`
4. GitHub Actions (`release.yml`) делает всё остальное:
   - xcodegen → тесты → build DMG → sign Sparkle EdDSA → GitHub Release → appcast.xml → Homebrew Cask

Соглашение: `CURRENT_PROJECT_VERSION` = последний сегмент semver (patch). Для `v0.1.11` → 11.

**Secrets (GitHub repo Settings → Secrets):**

| Secret | Что |
|--------|-----|
| `SPARKLE_PRIVATE_KEY` | EdDSA key из Keychain (`security find-generic-password -s "https://sparkle-project.org" -w`), base64-encoded |
| `RELEASE_PAT` | Fine-grained PAT (contents:write на govorun-app) — авторство релизов от sanyasamineva0x |
| `HOMEBREW_APP_ID` | GitHub App ID (3173509) |
| `HOMEBREW_APP_PRIVATE_KEY` | GitHub App PEM key |

**GitHub App "Govorun-app"** установлен на `homebrew-govorun` + `govorun-app`.

**Ручной (локальный) — если CI недоступен:**

1. Bump `project.yml`
2. `xcodegen generate`
3. `bash scripts/build-unsigned-dmg.sh`
4. `sign_update build/Govorun.dmg` (Sparkle EdDSA)
5. `gh release create vX.Y.Z build/Govorun.dmg`
6. Добавить `<item>` в `appcast.xml`, коммит + push
7. Обновить `homebrew-govorun/Casks/govorun.rb`, коммит + push

`sign_update` находится в DerivedData:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*"
```

Homebrew tap clone:
```bash
git clone https://github.com/sanyasamineva0x/homebrew-govorun.git /tmp/homebrew-govorun
```

## Структура

```
Govorun/
├── GovorunApp.swift
├── Info.plist                     # CFBundleVersion, Sparkle config, SUScheduledCheckInterval
├── Govorun.entitlements
├── App/
│   ├── AppState.swift             # Composition root, wiring, pendingActivationKey/RecordingMode
│   ├── StatusBarController.swift  # Menu bar icon (AppIcon в idle, SF Symbols при записи)
│   ├── BottomBarWindow.swift      # NSPanel pill (NSVisualEffectView legacy, glass на macOS 26)
│   ├── BottomBarView.swift        # SwiftUI pill content, OrganicPillShape, glass morphing
│   ├── SettingsWindowController.swift
│   ├── OnboardingWindowController.swift
│   ├── AXTextInserter.swift
│   ├── SystemSoundPlayer.swift
│   ├── NSEventMonitoring.swift    # CGEventTap + fallback, onTapReset для toggle
│   └── PostInsertionProviders.swift
├── Core/
│   ├── ActivationKeyMonitor.swift # modifier/keyCode/combo + push-to-talk/toggle
│   ├── SessionManager.swift
│   ├── PipelineEngine.swift
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
│   ├── ASRWorkerManager.swift     # venvPath injectable, needsSetup checks disk
│   ├── LocalSTTClient.swift       # 300s fixed timeout, precondition, setsockopt check
│   ├── ModelManager.swift
│   ├── STTClient.swift
│   ├── LLMClient.swift            # PlaceholderLLMClient → GigaChat 3.1 Lightning (Phase 5)
│   ├── UpdaterService.swift       # Sparkle 2, UpdateChecking protocol, @MainActor
│   └── AnalyticsService.swift
├── Models/
│   ├── ActivationKey.swift        # Sendable, Codable, displayName
│   ├── RecordingMode.swift        # pushToTalk / toggle, migration от "hold"
│   ├── TextMode.swift
│   ├── DictionaryEntry.swift
│   ├── Snippet.swift
│   ├── HistoryItem.swift
│   └── AnalyticsEvent.swift
├── Storage/
│   ├── SettingsStore.swift        # activationKey (JSON), recordingMode, logging на fallback
│   ├── DictionaryStore.swift
│   ├── SnippetStore.swift
│   ├── HistoryStore.swift
│   ├── AudioHistoryStorage.swift
│   └── MetricsAggregator.swift
├── Views/
│   ├── KeyRecorderView.swift      # UI recorder + hover + pencil icon
│   ├── SettingsView.swift         # Picker режима работы в секции Поведение
│   ├── SettingsTheme.swift        # settingsCard(), BrandedButton, colorScheme-aware stroke
│   ├── HistoryView.swift
│   ├── DictionaryView.swift
│   ├── SnippetListView.swift
│   ├── OnboardingView.swift       # Фирменный стиль, BrandedButton, staggeredAppear
│   └── AppModeSettingsView.swift
└── Resources/
    ├── Assets.xcassets            # AppIcon (bird + waveform)
    └── Sounds/
GovorunTests/                      # 761 тестов
worker/                            # Python ASR worker
├── server.py
├── requirements.txt
├── setup.sh
├── test_server.py
└── VERSION
scripts/
├── build-unsigned-dmg.sh          # Гарантированно копирует framework + worker + wheels
├── build-dmg.sh                   # Signed + notarized (нужен Developer ID)
├── fetch-python-framework.sh      # Скачивает Python 3.13, fix install_name_tool
└── download-wheels.sh             # Скачивает wheels для офлайн pip install
Frameworks/
└── Python.framework/              # В .gitignore! Скачать через fetch-python-framework.sh
appcast.xml                        # Sparkle feed (обновлять при каждом релизе)
docs/
├── recording-mode-spec.md
├── liquid-pill-spec.md
└── liquid-glass-plan.md
```

## Команды

```bash
# Тесты (CLI)
xcodebuild test -scheme Govorun -destination 'platform=macOS'

# Python worker тесты
cd worker && python3 -m pytest test_server.py -v

# Собрать и запустить тестовую версию (однострочник)
pkill -f Govorun 2>/dev/null; sleep 1; bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)' && rm -rf /Applications/Govorun.app && hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null && MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}') && cp -R "$MOUNT/Govorun.app" /Applications/ && hdiutil detach "$MOUNT" 2>/dev/null && xattr -cr /Applications/Govorun.app && open /Applications/Govorun.app

# Перезапустить установленную версию
pkill -f Govorun 2>/dev/null; sleep 1; open /Applications/Govorun.app

# Подписать DMG для Sparkle
$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*") build/Govorun.dmg

# Чистая установка через Cask
brew uninstall --cask govorun 2>/dev/null; rm -rf ~/.govorun; defaults delete com.govorun.app 2>/dev/null
cd /opt/homebrew/Library/Taps/sanyasamineva0x/homebrew-govorun && git pull
brew install --cask govorun
```

## Модели

| Модель | Размер | RAM | Назначение | Статус |
|--------|--------|-----|------------|--------|
| GigaAM-v3 e2e_rnnt (3 ONNX, fp32) | ~892 MB | ~1.5 GB | ASR | Используется |
| Silero VAD (ONNX) | ~2 MB | ~50 MB | Нарезка аудио | Используется |
| GigaChat 3.1 Lightning (GGUF Q4_K_M) | ~TBD | ~TBD | Нормализация текста (Phase 5) | Планируется |

ASR кэш: `~/.cache/huggingface/hub/`

### Phase 5: LLM нормализация

Текущий `PlaceholderLLMClient` будет заменён на локальный инференс GigaChat 3.1 Lightning (GGUF Q4_K_M).
Задача: умная нормализация после ASR — пунктуация, стиль, контекстные замены.
Инференс полностью офлайн, без API. Runtime: llama.cpp или MLX.

## Известные особенности

- **Accessibility сбрасывается при reinstall** — macOS привязывает permission к code signature. При Cask reinstall нужно переключить тогл в настройках Универсального доступа.
- **Sparkle обновления сохраняют Accessibility** — replace in place, signature та же.
- **Python.framework и wheels в .gitignore** — скачивать через scripts/.
- **Flaky тест** `test_stop_then_start_relaunches_worker` — race condition на CI, не блокер.
- **Xcode 26.3** — objectVersion 77 native, perl hack не нужен.
