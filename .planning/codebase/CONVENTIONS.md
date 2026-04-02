# Conventions

Reference: `/CLAUDE.md`, `/AGENTS.md`, `project.yml`, production source under `Govorun/`.

---

## Language and Comments

- **Swift 5.10+**, macOS 14.0+, Apple Silicon (M1+).
- **Python 3.13** for the worker (`worker/`).
- Comments are minimal and written in Russian.
- No English comments in Swift unless it is a compiler-required string (e.g., Swift doc comments are not used at all).

---

## Commit Conventions

Format: `feat: добавить X` / `fix: исправить Y` — Russian, conventional-commits prefix.

- **No `Co-Authored-By`** lines. The repo is public and must show no signs of AI authorship.
- Branch names: `feat/<name>` or `fix/<name>`.
- Never commit to `main` directly. One live branch at a time.
- Merge strategy: squash merge → delete branch.

---

## Swift Code Style

### Naming

- Types (classes, structs, enums, protocols): `UpperCamelCase` — e.g., `PipelineEngine`, `STTClient`, `SnippetMatching`.
- Functions and properties: `lowerCamelCase` — e.g., `recognizeCalls`, `normalizeResult`.
- Private stored properties that back a computed interface use `_` prefix with a lock, e.g.:

```swift
private var _state: SuperAssetsState = .unknown
var state: SuperAssetsState {
    lock.lock(); defer { lock.unlock() }; return _state
}
```

- Constants in `Settings` stores use a nested `private enum Keys` with `static let` string keys:

```swift
private enum Keys {
    static let productMode = "productMode"
    static let recordingMode = "recordingMode"
}
```

- Static configuration constants use `static let default*` naming, e.g.:
  `LocalLLMConfiguration.defaultBaseURLString`, `LocalLLMConfiguration.defaultRequestTimeout`.

### Imports

- Every file imports only what it needs — no wildcard framework blanket imports.
- Typical per-layer imports:
  - `Core/` — `Foundation` only (sometimes `OSLog`). Never `AppKit` or `SwiftUI`.
  - `Services/` — `Foundation` + `OSLog`. Never `AppKit`.
  - `Models/` — `Foundation` or `CoreGraphics`. Never `AppKit` or `SwiftUI`.
  - `Storage/` — `Foundation` + `SwiftData`.
  - `App/` — `Cocoa`, `SwiftUI`, `Combine`, `SwiftData` as needed.
  - `Views/` — `SwiftUI`.
- Import order: system frameworks alphabetically, no blank lines between them (no third-party packages in most files — Sparkle is only wired in `UpdaterService`).

### Async / Concurrency

- **async/await everywhere** — no completion handlers in new code.
- **`@MainActor` only for UI code** — `AppState`, `StatusBarController`, `BottomBarController`, `SettingsWindowController`, `OnboardingWindowController`, and all `Views/`.
- `SWIFT_STRICT_CONCURRENCY: complete` is set in `project.yml` — the compiler enforces this.
- Thread-safe mutable state in non-actor types: `NSLock` + `lock.lock()/unlock()` or `lock.withLock { }`.
- `@unchecked Sendable` is used only on concrete final classes that manage their own lock, never on value types.
- `CheckedContinuation` for bridging synchronous callbacks to async, e.g. `ControlledSTTClient` in tests.

### Error Handling

Errors are **typed enums**, never `NSError` or untyped `Error`. Pattern:

```swift
enum STTError: Error, Equatable {
    case noAudioData
    case connectionFailed(String)
    case recognitionFailed(String)
    case noResult
}
```

- Conform to `LocalizedError` when the error is shown to users; add `var errorDescription: String?`.
- Always conform to `Equatable` so errors can be asserted in tests.
- Full inventory of typed errors:
  - `STTError` — `Services/STTClient.swift`
  - `LLMError` — `Services/LLMClient.swift`
  - `LLMRuntimeError: Error, Equatable, LocalizedError` — `Services/LLMRuntimeManager.swift`
  - `WorkerError: Error, Equatable, LocalizedError` — `Services/ASRWorkerManager.swift`
  - `PipelineError: Error, Equatable` — `Core/PipelineEngine.swift`
  - `AudioCaptureError: Error, Equatable` — `Core/AudioCapture.swift`
  - `TextInsertionError: Error, Equatable` — `Core/TextInserter.swift`
  - `SuperModelDownloadError: Error, LocalizedError, Equatable` — `Models/SuperModelDownloadState.swift`
  - `DictionaryStoreError: Error` — `Storage/DictionaryStore.swift`
  - `SnippetStoreError: Error` — `Storage/SnippetStore.swift`
- **No force unwrap (`!`) in production code.** Use `guard let` / optional chaining / safe fallbacks.
- Decoding fallback pattern (e.g. `ActivationKey.init(from:)` in `Models/ActivationKey.swift`): on any decoding failure, fall back to `.default` with a `print` log — never crash.

### Protocols (Dependency Injection)

All injectable services are defined as protocols so tests can substitute mocks:

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

Enforced via import discipline (verified by absence of cross-layer imports):

```
Core/     — pure Swift, no AppKit, no SwiftUI
Services/ — Foundation + OSLog, no AppKit
Models/   — value types, Foundation/CoreGraphics only
Storage/  — Foundation + SwiftData
App/      — Cocoa, Combine, SwiftData (composition root)
Views/    — SwiftUI
worker/   — Python only, communicates via unix socket
```

`AppState` (`App/AppState.swift`) is the **composition root** — it wires all protocols to concrete implementations at startup.

### Logging

`OSLog` / `Logger` with subsystem `com.govorun.app` and per-class category:

```swift
private static let logger = Logger(subsystem: "com.govorun.app", category: "PipelineEngine")
```

Used in: `AppState`, `PipelineEngine`, `SuperAssetsManager`, `SuperModelDownloadManager`, `LocalLLMClient`, `LLMRuntimeManager`.

Simple `print()` statements appear only for fallback/migration paths in Models layer where OSLog is not imported.

### Platform / API Guards

Liquid Glass API (macOS 26 / Xcode 26) is guarded at two levels:

```swift
#if compiler(>=6.2)
    if #available(macOS 26, *) {
        // Liquid Glass code
    }
#endif
```

Both guards required — `compiler(>=6.2)` prevents build errors on Xcode 15.4 (which ships Swift < 6.2).

---

## Python Conventions

- All in `worker/`.
- Module entry point: `worker/server.py`.
- Protocol comments at module top, in Russian.
- `atexit` + signal handlers for cleanup (socket file removal).
- stdout is used as a **machine-readable protocol** parsed by `ASRWorkerManager` — lines like `LOADING model=...`, `LOADED 3.2s`, `READY`.
- Error responses over JSON: `{"error": "oom|file_not_found|internal", "message": "..."}`.
- Dependencies pinned in `worker/requirements.txt` with exact versions.

---

## Settings / UserDefaults Pattern

`SettingsStore` (`Storage/SettingsStore.swift`) wraps `UserDefaults`:

- Injectable `defaults` parameter for test isolation.
- Keys in a `private enum Keys` nested type.
- `registerDefaults()` called in `init` so all keys have sensible fallbacks without explicit nil checks.
- Migration logic in `init` for breaking changes (e.g., `migrateRecordingMode()`).
- Tests always use a UUID-suffixed suite name to prevent cross-test pollution:

```swift
let defaults = UserDefaults(suiteName: "com.govorun.tests.\(UUID().uuidString)")!
```

---

## SwiftData Pattern

- In-memory containers for tests:

```swift
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: DictionaryEntry.self, configurations: config)
```

- Production app uses two named configurations in one container (`"main"` + `"analytics"`) — see `GovorunApp.swift`.

---

## Versioning

`project.yml` controls `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Both must match the git tag at release time — `release.yml` CI enforces this with an explicit validation step.
