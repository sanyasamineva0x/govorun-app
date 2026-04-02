# Говорун

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн.
Зажал клавишу → сказал → отпустил → чистый текст в активном поле.

## Стек

- Swift 5.10+, macOS 14.0+ (Sonoma), Apple Silicon (M1+)
- SwiftUI + AppKit (NSStatusItem, NSPanel, NSEvent, AXUIElement)
- Python 3.13 worker (unix socket IPC, embedded Python.framework)
- onnx-asr (GigaAM-v3 e2e_rnnt), Silero VAD
- GigaChat 3.1 10B-A1.8B Q4_K_M (llama-server, Говорун Super)
- Sparkle 2 (автообновление EdDSA), SwiftData
- XCTest (986 тестов)

## Конвенции

- Язык кода: Swift + Python. Комментарии минимальные, на русском
- Коммиты на русском: `feat: добавить X`, `fix: исправить Y`
- **Нет Co-Authored-By** — публичный репо, без признаков AI
- TDD: тест (red) → код (green) → рефактор
- Все сервисы через протоколы (STTClient, LLMClient, SuperAssetsManaging, LLMRuntimeManaging)
- Моки в тестах, никогда реальный Python worker или модели
- Ошибки типизированы: `enum XxxError: Error, LocalizedError { ... }`
- async/await, не completion handlers
- @MainActor только для UI-кода
- Нет force unwrap (!) в production коде
- Zero API credentials — всё локально
- Liquid Glass API за `#if compiler(>=6.2)` + `#available(macOS 26, *)`

## Слои

- Core/ НЕ импортирует SwiftUI или AppKit (чистый Swift)
- Services/ НЕ импортирует AppKit
- Models/ — чистые value types
- worker/ — Python, общается ТОЛЬКО через unix socket

## Сборка

**ВАЖНО: приложение не запускается через ⌘R без подготовки.**

```bash
# Первая сборка
bash scripts/fetch-python-framework.sh  # Python.framework (63 МБ)
bash scripts/download-wheels.sh         # wheels для pip (124 МБ)
bash scripts/build-llama-server.sh      # Static llama-server arm64 (12 МБ, ~5 мин)
xcodegen generate

# Собрать DMG и установить (однострочник)
pkill -f Govorun 2>/dev/null; sleep 1; bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)' && rm -rf /Applications/Govorun.app && hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null && MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}') && cp -R "$MOUNT/Govorun.app" /Applications/ && hdiutil detach "$MOUNT" 2>/dev/null && xattr -cr /Applications/Govorun.app && open /Applications/Govorun.app
```

DMG — единственный надёжный способ тестирования. Accessibility сбрасывается при каждой переустановке.

## Команды

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation  # Swift тесты
cd worker && python3 -m pytest test_server.py -v  # Python тесты
xcodegen generate  # После изменений project.yml
```

## Git-процесс

- `feat/<name>` или `fix/<name>` → PR → squash merge → delete branch
- Не коммитить в main напрямую
- Одна живая ветка за раз

## Релиз

Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` в `project.yml` → коммит → `git tag v0.X.Y && git push --tags` → CI делает всё (xcodegen → тесты → DMG → Sparkle EdDSA → GitHub Release → appcast.xml → Homebrew Cask).

## Pipeline

```
Activation key → AudioCapture (16kHz) → STT (unix socket → Python worker → GigaAM) →
→ DictionaryStore → SnippetEngine →
→ DeterministicNormalizer (филлеры, числа, бренды, канон) →
→ [Говорун Super?] → LocalLLMClient → NormalizationGate →
→ TextInserter (AX → composition → clipboard)
```

Два режима:
- **Говорун** (standard) — deterministic only, дефолт, всегда работает
- **Говорун Super** — deterministic + LLM, opt-in, требует llama-server + GGUF

## Модели

| Модель | Размер | RAM | Путь |
|--------|--------|-----|------|
| GigaAM-v3 e2e_rnnt (3 ONNX) | ~892 MB | ~1.5 GB | `~/.cache/huggingface/hub/` |
| Silero VAD (ONNX) | ~2 MB | ~50 MB | в bundle |
| GigaChat 3.1 Q4_K_M | ~6 GB | ~7-8 GB | `~/.govorun/models/gigachat-gguf.gguf` (скачивается автоматически) |

LLM параметры: temperature=0, max_tokens=128, stop=["\n\n"], llama-server localhost:8080.

Скачивание модели: `SuperModelDownloadManager` → HF `ai-sage/GigaChat3.1-10B-A1.8B-GGUF` (pinned commit). Resume через Range + `.partial.meta`. SHA256 верификация.

## IPC (unix socket)

`~/.govorun/worker.sock`. JSON: `{"wav_path": "..."}` → `{"text": "..."}`. Stateless, 300s timeout.

## Известные особенности

- Python.framework, wheels, Helpers/llama-server в .gitignore — скачивать/собирать через scripts/
- Accessibility сбрасывается при reinstall (code signature), Sparkle сохраняет
- Flaky тест `test_stop_then_start_relaunches_worker` — race condition, не блокер

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Стили текста v2 (shipped v1.0)**

SuperTextStyle (relaxed/normal/formal) заменила TextMode. SuperStyleEngine определяет стиль по bundleId в авто-режиме. Вкладка "Стиль текста" в menubar с авто/ручной. TextMode полностью удалён.

**Core Value:** Стиль текста адаптируется к контексту — расслабленный в мессенджерах, формальный в почте, обычный везде остальном. Одна точка настройки вместо per-app оверрайдов.

**Known limitation:** applyDeterministic (trivial/snippet/fallback paths) — только caps, без brand aliases и slang expansion. Однословные бренды/сленг не доходят до LLM (isTrivial gate). Scope для v2.

### Constraints

- **Tech stack**: Swift 5.10+, macOS 14.0+, Apple Silicon only
- **Architecture**: Core/ без SwiftUI/AppKit, Services/ без AppKit, Models/ чистые value types
- **Testing**: TDD, моки через протоколы, без реального Python worker или LLM
- **Conventions**: коммиты на русском, без Co-Authored-By, минимальные комментарии на русском
- **Backward compat**: HistoryItem.textMode поле остаётся String, без SwiftData migration
- **Trivial path**: короткие фразы без LLM — applyDeterministic покрывает только caps и точку (осознанный компромисс)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
| Language | Version | Role |
|----------|---------|------|
| Swift | 5.10 (`SWIFT_VERSION` in `project.yml`) | Main application |
| Python | 3.13 (embedded `Python.framework`) | ASR worker subprocess |
| Bash | system | Build and release scripts |
## Platform & Runtime Requirements
- **macOS deployment target**: 14.0 (Sonoma) — set in `project.yml` and `Govorun/Info.plist`
- **Architecture**: arm64 only (Apple Silicon M1+)
- **Xcode version**: 15.4 (`options.xcodeVersion` in `project.yml`)
- **Swift strict concurrency**: `complete` (set in `project.yml` base settings)
- **Bundle ID**: `com.govorun.app`
- **Marketing version**: `0.2.0` / build `0` (in `project.yml`)
## Swift Application
### UI Frameworks
- **SwiftUI** — settings views, onboarding, history, dictionary, snippet list
- **AppKit** — `NSStatusItem` (menu bar), `NSPanel` (bottom bar HUD), `NSEvent` (global hotkeys), `NSWorkspace` (frontmost app detection), `NSPasteboard` (clipboard)
- **ApplicationServices** — `AXUIElement` API for accessibility-based text insertion
- **AVFoundation** — `AVAudioEngine` for microphone capture at 16kHz PCM Int16 mono
- **Combine** — `ObservableObject`, `@Published`, publisher subscriptions (e.g. Sparkle `canCheckForUpdates`)
### Apple System Frameworks Used
- `Foundation` — throughout
- `OSLog` — structured logging (`Logger(subsystem:category:)`)
- `SwiftData` — local database (see Storage section)
- `ServiceManagement` — `SMAppService.mainApp` for launch-at-login
- `CryptoKit` — `SHA256` for GGUF model integrity verification
- `CoreGraphics` — `CGEvent` for synthetic keyboard paste (`Cmd+V`)
### Third-Party Swift Packages
| Package | Version | Source |
|---------|---------|--------|
| **Sparkle** | >= 2.7.2 | `https://github.com/sparkle-project/Sparkle` |
## Python Worker
### Runtime
- Python 3.13 embedded as `Frameworks/Python.framework` (fetched via `scripts/fetch-python-framework.sh` from `python.org`)
- Virtual environment created at `~/.govorun/venv/` by `worker/setup.sh` on first run or VERSION change
- Worker version: `3` (stored in `worker/VERSION`)
### Python Dependencies (`worker/requirements.txt`)
| Package | Version | Purpose |
|---------|---------|---------|
| `onnx-asr` | 0.10.2 | ONNX-based ASR pipeline wrapper for GigaAM |
| `onnxruntime` | 1.23.2 | ONNX model inference (CPUExecutionProvider only — CoreML disabled) |
| `huggingface-hub` | 1.7.1 | Model download from HuggingFace (`snapshot_download`) |
| `numpy` | 2.2.6 | Audio data handling |
| `silero-vad` | 6.2.1 | Voice activity detection segmentation |
### Vendored Wheels (`worker/wheels/`)
## LLM Runtime (Govorun Super)
- **llama-server**: Static arm64 binary built from `llama.cpp @ b8500` (tag `b8500`)
- Build script: `scripts/build-llama-server.sh`
- CMake flags: `DGGML_METAL=ON`, `DGGML_METAL_EMBED_LIBRARY=ON`, `DGGML_BLAS=ON` (Apple BLAS), `BUILD_SHARED_LIBS=OFF`, `LLAMA_CURL=OFF`
- Binary location in bundle: `Govorun.app/Contents/Helpers/llama-server`
- Build output before bundling: `Helpers/llama-server`
- Constraint: only system framework dependencies allowed (`/System/Library/Frameworks/`, `/usr/lib/`)
## Build System
### XcodeGen
- **Config file**: `project.yml`
- Generates `Govorun.xcodeproj` — not committed (regenerated by `xcodegen generate`)
- Copy Files phases in `project.yml` bundle: `worker/server.py`, `worker/setup.sh`, `worker/requirements.txt`, `worker/VERSION`, `worker/wheels/` (folder), `Frameworks/Python.framework` (code-signed)
### Xcode Build
- `xcodebuild archive` then manual copy — no `exportArchive` (unsigned DMG, no Developer ID)
- Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) with entitlement `com.apple.security.device.audio-input`
- Hardened Runtime: enabled in both Debug and Release configs
### DMG Packaging
- Script: `scripts/build-unsigned-dmg.sh`
- Output: `build/Govorun.dmg`
- DMG volume name: `Говорун`
- Format: UDZO (zlib-compressed)
### GitHub Actions CI/CD
- **Tests workflow** (`/.github/workflows/tests.yml`): triggers on PR/push to `main`
- **Release workflow** (`/.github/workflows/release.yml`): triggers on `v*` tags
## Code Formatting
- **SwiftFormat** config: `.swiftformat`
- Swift version: `5.10`
- Notable rules: `--decimal-grouping 3,4`, `--wrap-collections before-first`, `--wrap-parameters before-first`
## Testing
- **XCTest** — Swift unit tests in `GovorunTests/` (~986 tests across 38 files)
- **pytest** — Python worker tests in `worker/test_server.py`
- Test plan: `Govorun.xctestplan`
- All tests use mocks; no real Python worker or ML models loaded during tests
## Storage
- **SwiftData** — two SQLite databases via `AppModelContainer` in `Govorun/GovorunApp.swift`:
- **UserDefaults** — settings (`SettingsStore`), worker installed version (`govorun.worker.installedVersion`)
- **FileSystem** — audio history WAV files at `~/Library/Application Support/com.govorun.app/AudioHistory/`
## Configuration Files
| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project definition (targets, packages, build settings, copy phases) |
| `Govorun/Info.plist` | Bundle metadata, Sparkle feed URL, microphone usage description, `LSUIElement=true` |
| `Govorun/Govorun.entitlements` | Single entitlement: `com.apple.security.device.audio-input` |
| `ExportOptions.plist` | Xcode archive export options (unused in unsigned DMG flow) |
| `Govorun.xctestplan` | XCTest plan |
| `.swiftformat` | SwiftFormat rules |
| `worker/requirements.txt` | Python pip dependencies |
| `worker/VERSION` | Worker protocol version (`3`) — triggers venv rebuild on change |
| `worker/setup.sh` | Creates `~/.govorun/venv/`, installs wheels |
| `appcast.xml` | Sparkle update feed (hosted on GitHub raw, updated by CI) |
| `.github/workflows/release.yml` | Full release pipeline |
| `.github/workflows/tests.yml` | PR/push test runner |
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Language and Comments
- **Swift 5.10+**, macOS 14.0+, Apple Silicon (M1+).
- **Python 3.13** for the worker (`worker/`).
- Comments are minimal and written in Russian.
- No English comments in Swift unless it is a compiler-required string (e.g., Swift doc comments are not used at all).
## Commit Conventions
- **No `Co-Authored-By`** lines. The repo is public and must show no signs of AI authorship.
- Branch names: `feat/<name>` or `fix/<name>`.
- Never commit to `main` directly. One live branch at a time.
- Merge strategy: squash merge → delete branch.
## Swift Code Style
### Naming
- Types (classes, structs, enums, protocols): `UpperCamelCase` — e.g., `PipelineEngine`, `STTClient`, `SnippetMatching`.
- Functions and properties: `lowerCamelCase` — e.g., `recognizeCalls`, `normalizeResult`.
- Private stored properties that back a computed interface use `_` prefix with a lock, e.g.:
- Constants in `Settings` stores use a nested `private enum Keys` with `static let` string keys:
- Static configuration constants use `static let default*` naming, e.g.:
### Imports
- Every file imports only what it needs — no wildcard framework blanket imports.
- Typical per-layer imports:
- Import order: system frameworks alphabetically, no blank lines between them (no third-party packages in most files — Sparkle is only wired in `UpdaterService`).
### Async / Concurrency
- **async/await everywhere** — no completion handlers in new code.
- **`@MainActor` only for UI code** — `AppState`, `StatusBarController`, `BottomBarController`, `SettingsWindowController`, `OnboardingWindowController`, and all `Views/`.
- `SWIFT_STRICT_CONCURRENCY: complete` is set in `project.yml` — the compiler enforces this.
- Thread-safe mutable state in non-actor types: `NSLock` + `lock.lock()/unlock()` or `lock.withLock { }`.
- `@unchecked Sendable` is used only on concrete final classes that manage their own lock, never on value types.
- `CheckedContinuation` for bridging synchronous callbacks to async, e.g. `ControlledSTTClient` in tests.
### Error Handling
- Conform to `LocalizedError` when the error is shown to users; add `var errorDescription: String?`.
- Always conform to `Equatable` so errors can be asserted in tests.
- Full inventory of typed errors:
- **No force unwrap (`!`) in production code.** Use `guard let` / optional chaining / safe fallbacks.
- Decoding fallback pattern (e.g. `ActivationKey.init(from:)` in `Models/ActivationKey.swift`): on any decoding failure, fall back to `.default` with a `print` log — never crash.
### Protocols (Dependency Injection)
| Protocol | Location | Purpose |
|---|---|---|
| `STTClient` | `Services/STTClient.swift` | Speech recognition |
| `LLMClient` | `Services/LLMClient.swift` | Text normalization |
| `SuperAssetsManaging` | `Services/SuperAssetsManager.swift` | Runtime + model check |
| `LLMRuntimeManaging` | `Services/LLMRuntimeManager.swift` | llama-server lifecycle |
| `SuperModelDownloading` | `Services/SuperModelDownloadManager.swift` | Model download |
| `ASRWorkerManaging` | `Services/ASRWorkerManager.swift` | Python worker lifecycle |
| `TextInserting` | `Core/TextInserter.swift` | Text insertion |
| `AnalyticsEmitting` | `Core/AnalyticsEmitting.swift` | Analytics |
| `AudioRecording` | `Core/AudioCapture.swift` | Audio capture |
| `SnippetMatching` | `Core/SnippetEngine.swift` | Snippet lookup |
| `EventMonitoring` | `App/NSEventMonitoring.swift` | Key event monitoring |
| `AccessibilityProviding` | `Core/TextInserter.swift` | AX API |
| `ClipboardProviding` | `Core/TextInserter.swift` | Clipboard |
| `FileChecking` | `Services/SuperAssetsManager.swift` | File system |
| `UpdateChecking` | `Services/UpdaterService.swift` | Sparkle updates |
### Layer Separation Rules
### Logging
### Platform / API Guards
#if compiler(>=6.2)
#endif
## Python Conventions
- All in `worker/`.
- Module entry point: `worker/server.py`.
- Protocol comments at module top, in Russian.
- `atexit` + signal handlers for cleanup (socket file removal).
- stdout is used as a **machine-readable protocol** parsed by `ASRWorkerManager` — lines like `LOADING model=...`, `LOADED 3.2s`, `READY`.
- Error responses over JSON: `{"error": "oom|file_not_found|internal", "message": "..."}`.
- Dependencies pinned in `worker/requirements.txt` with exact versions.
## Settings / UserDefaults Pattern
- Injectable `defaults` parameter for test isolation.
- Keys in a `private enum Keys` nested type.
- `registerDefaults()` called in `init` so all keys have sensible fallbacks without explicit nil checks.
- Migration logic in `init` for breaking changes (e.g., `migrateRecordingMode()`).
- Tests always use a UUID-suffixed suite name to prevent cross-test pollution:
## SwiftData Pattern
- In-memory containers for tests:
- Production app uses two named configurations in one container (`"main"` + `"analytics"`) — see `GovorunApp.swift`.
## Versioning
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Паттерн
## Слои
```
```
- `Core/` — нет SwiftUI, нет AppKit
- `Services/` — нет AppKit
- `Models/` — чистые value types
- `App/` — AppKit + SwiftUI, системные интеграции
## Точки входа
- `Govorun/GovorunApp.swift` — `@main struct GovorunApp: App`. LSUIElement=true, menu bar only.
- `applicationDidFinishLaunching` в `AppDelegate` — создаёт `SettingsStore`, `AppState`, `StatusBarController`; показывает онбординг если нужно, затем `state.start()`
- `worker/server.py` — unix socket сервер. Запускается `ASRWorkerManager` как дочерний процесс через embedded `Frameworks/Python.framework`
## Composition Root: AppState
```swift
```
- `wireActivationKeyMonitor()` — активация/деактивация → `SessionManager`
- `wireSessionManager()` — переходы состояний → pipeline/UI
- `wireAudioCapture()` — делегат AudioCapture → AppState
- `wireSnippetNotifications()` — NSNotification при изменении сниппетов
- `wireWorkerManager()` — состояние Python worker → `@Published workerState`
- `wireLLMRuntimeManager()` — состояние llama-server → `@Published llmRuntimeState`
- `wireSettingsChange()` — изменения SettingsStore (Combine) → pending settings
- `wireSleepNotification()` — системный sleep/wake → пауза worker
## Pipeline (основной путь данных)
```
```
- `standalone` — весь транскрипт = триггер → вставить `content` как есть, 0ms LLM
- `embedded` — триггер внутри фразы → инжект placeholder в LLM промпт → `SnippetReinserter.reinsert()`
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
| `WorkspaceProviding` | `Core/AppContextEngine.swift` | `NSWorkspaceProvider` (inline) |
| `SoundPlaying` | `Core/SoundManager.swift` | `SystemSoundPlayer`, `MuteSoundPlayer` |
| `PostInsertionMonitoring` | `Core/PostInsertionMonitor.swift` | `PostInsertionMonitor` |
## Concurrency модель
- `@MainActor` — AppState, ActivationKeyMonitor, SessionManager, StatusBarController, BottomBarController, PostInsertionMonitor, ModelManager
- `actor` — AnalyticsService (изолирует запись SwiftData)
- `@unchecked Sendable` + `NSLock` — PipelineEngine, ASRWorkerManager, LocalLLMClient, SnippetEngine, TextInserterEngine (ручная синхронизация для thread-safe доступа к mutable state)
- `async/await` — всё IPC и HTTP; никаких completion handlers
- Swift strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
## AppContextEngine (bundleId detection)
- `detectCurrentApp()` возвращает `AppContext(bundleId, appName)` через NSWorkspace
- `SuperStyleEngine.resolve(bundleId:mode:manualStyle:)` определяет стиль по bundleId в авто-режиме
- Мессенджеры (Telegram, WhatsApp, Viber, VK, iMessage, Discord, Slack) → relaxed
- Почта (Mail, Spark, Outlook) → formal
- Всё остальное → normal
## LLM Runtime (Говорун Super)
## Analytics
- zero-edit rate (§6.1)
- insertion success rate (§6.3)
- latency percentiles p50/p90/p95 (§6.4)
## Запуск приложения (cold start)
```
```
## CI/CD
- `/.github/workflows/tests.yml` — xcodebuild test + pytest
- `/.github/workflows/release.yml` — xcodegen → тесты → DMG → Sparkle EdDSA → GitHub Release → appcast.xml
- `appcast.xml` — Sparkle appcast (EdDSA подпись)
- `project.yml` — XcodeGen конфиг (не xcodeproj в git)
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
