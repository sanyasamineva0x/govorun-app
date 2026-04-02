# Integrations

## Overview

Govorun is a fully offline application. There are no external API calls during normal operation. All network activity is either local-machine IPC or update/download infrastructure. No authentication providers, no cloud services, no telemetry leaving the device.

---

## IPC: Unix Domain Socket (Swift ↔ Python ASR Worker)

**Type**: Unix domain socket, `AF_UNIX / SOCK_STREAM`

**Socket path**: `~/.govorun/worker.sock`

**Direction**: Swift app → Python worker (one request per connection, stateless)

**Protocol**: newline-terminated JSON over a single connect/send/recv/close cycle

Request types:
```
ASR:  {"wav_path": "/tmp/govorun_<uuid>.wav"}   → {"text": "..."}
Ping: {"cmd": "ping"}                            → {"status": "ok", "version": "3"}
Error response: {"error": "oom|file_not_found|internal", "message": "..."}
```

**stdout protocol** (Python → Swift, parsed by `ASRWorkerManager`):
```
LOADING model=gigaam-v3-e2e-rnnt vad=silero version=3
LOADED <seconds>s
DOWNLOADING <pct>%
READY
```

**Relevant files**:
- Swift client: `Govorun/Services/LocalSTTClient.swift`
- Swift worker manager: `Govorun/Services/ASRWorkerManager.swift`
- Python server: `worker/server.py`

**Socket directory permissions**: `0o700` (owner-only access)

**Security**: Path traversal protection in `server.py` — only `/tmp/` prefixes accepted for `wav_path`

**Timeouts**: Swift client uses `SO_RCVTIMEO`/`SO_SNDTIMEO` (300s default). Python server drops connections after 30s inactivity.

---

## IPC: HTTP localhost (Swift ↔ llama-server)

**Type**: HTTP/1.1 over TCP loopback

**Endpoint base URL**: `http://127.0.0.1:8080/v1` (configurable via `GOVORUN_LLM_BASE_URL` env var or settings)

**Relevant files**:
- Swift client: `Govorun/Services/LocalLLMClient.swift`
- Runtime manager: `Govorun/Services/LLMRuntimeManager.swift`

**Endpoints used**:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/v1/models` | Healthcheck — verifies model alias is loaded |
| `POST` | `/v1/chat/completions` | Text normalization inference |

**Chat completion request shape** (OpenAI-compatible):
```json
{
  "model": "gigachat-gguf",
  "temperature": 0.0,
  "max_tokens": 128,
  "stop": ["\n\n"],
  "stream": false,
  "messages": [
    {"role": "system", "content": "<mode-specific system prompt>"},
    {"role": "user",   "content": "<transcribed text>"}
  ]
}
```

**Timeouts**: request 12s, healthcheck 1.5s. Healthcheck TTL 30s (cached success). Failure cooldown 5s.

**llama-server launch args** (assembled in `LLMRuntimeManager`):
```
llama-server --host 127.0.0.1 --port 8080 --model <path> --alias gigachat-gguf --ctx-size 4096 --n-gpu-layers -1
```

**Environment variable overrides**:
- `GOVORUN_LLM_BASE_URL` — override endpoint
- `GOVORUN_LLM_MODEL` — override model alias
- `GOVORUN_LLM_MODEL_PATH` — override GGUF file path
- `GOVORUN_LLM_RUNTIME_BIN` — override llama-server binary path
- `GOVORUN_LLM_TIMEOUT` — override request timeout
- `GOVORUN_LLM_HEALTHCHECK_TIMEOUT` — override healthcheck timeout
- `GOVORUN_LLM_HEALTHCHECK_TTL` — override healthcheck cache TTL
- `GOVORUN_LLM_FAILURE_COOLDOWN` — override failure cooldown
- `GOVORUN_LLM_MAX_TOKENS` — override max output tokens
- `GOVORUN_LLM_TEMPERATURE` — override temperature
- `GOVORUN_LLM_CTX_SIZE` — override context size
- `GOVORUN_LLM_GPU_LAYERS` — override GPU layers
- `GOVORUN_LLM_STARTUP_TIMEOUT` — override startup timeout
- `GOVORUN_LLM_HEALTHCHECK_INTERVAL` — override healthcheck poll interval

---

## Model Download: HuggingFace Hub (Python, lazy on first run)

**Type**: HTTPS direct download via `huggingface-hub` Python library

**Trigger**: Python worker calls `onnx_asr.load_model("gigaam-v3-e2e-rnnt")` on startup if model not cached

**Model**: GigaAM-v3 e2e_rnnt (3 ONNX files, ~892 MB total)

**Cache location**: `~/.cache/huggingface/hub/` (standard HuggingFace cache)

**Progress reporting**: monkey-patched `tqdm_class` in `worker/server.py` writes `DOWNLOADING <pct>%` to stdout, parsed by `ASRWorkerManager.handleStdoutLine()`

**Relevant files**: `worker/server.py` (lines 68–111), `Govorun/Services/ASRWorkerManager.swift`

---

## Model Download: HuggingFace Direct URL (Swift, Govorun Super)

**Type**: HTTPS with HTTP Range resume support

**URL** (pinned commit): `https://huggingface.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF/resolve/97045b260251cfa86f5ad25638fa2dd074153446/GigaChat3.1-10B-A1.8B-q4_K_M.gguf`

**Destination**: `~/.govorun/models/gigachat-gguf.gguf`

**Expected size**: 6,474,702,976 bytes (~6 GB)

**Expected SHA256**: `68a8732fb5cee04f83ebffd7924e15c534d4442c5a43d2ba9e2041fe310b8deb`

**Resume mechanism**: `.partial` + `.partial.meta` sidecar files. `PartialDownloadMeta` stores url, expectedSHA256, expectedSize, etag, downloadedBytes. On restart, sends `Range: bytes=<offset>-` header if ETag and SHA256 match.

**Integrity check**: `CryptoKit.SHA256` streaming hash of completed file. On mismatch, partial file is deleted.

**Disk space check**: requires `expectedSize - partialSize + 500 MB` buffer (`SuperModelCatalog.minimumDiskSpaceBuffer`)

**Relevant files**:
- `Govorun/Models/SuperModelCatalog.swift` — URL, SHA256, size constants
- `Govorun/Models/SuperModelDownloadSpec.swift` — download spec type
- `Govorun/Models/SuperModelDownloadState.swift` — state enum
- `Govorun/Services/SuperModelDownloadManager.swift` — download implementation
- `Govorun/Services/SuperAssetsManager.swift` — checks if runtime binary and model exist

---

## Auto-Update: Sparkle 2

**Type**: HTTPS appcast polling + EdDSA signature verification

**Feed URL**: `https://raw.githubusercontent.com/sanyasamineva0x/govorun-app/main/appcast.xml` (in `Govorun/Info.plist` key `SUFeedURL`)

**Public EdDSA key**: `5CA1augvUYfLvo4JFzOFm1mau3AGOp7Lt1rpfIPAeiM=` (in `Govorun/Info.plist` key `SUPublicEDKey`)

**Check interval**: 3600 seconds (`SUScheduledCheckInterval` in `Govorun/Info.plist`)

**Auto-check**: enabled (`SUAutomaticallyCheckForUpdates = true`)

**Download URL pattern**: `https://github.com/sanyasamineva0x/govorun-app/releases/download/v<version>/Govorun.dmg`

**Signing**: `sign_update` tool from Sparkle DerivedData, private key stored as GitHub secret `SPARKLE_PRIVATE_KEY`

**Relevant files**:
- `Govorun/Services/UpdaterService.swift` — `SPUUpdater` wrapper
- `Govorun/Info.plist` — Sparkle config keys
- `appcast.xml` — feed file, updated by CI on each release
- `.github/workflows/release.yml` — steps 16 (sign), 19 (update appcast)

---

## Distribution: Homebrew Cask

**Tap**: `sanyasamineva0x/homebrew-govorun` (separate repo)

**Cask file**: `Casks/govorun.rb`

**Update mechanism**: CI clones the tap repo and `sed`-patches version and SHA256 on each release (step 21 in `release.yml`)

**GitHub App token**: generated via `actions/create-github-app-token@v1` using secrets `HOMEBREW_APP_ID` and `HOMEBREW_APP_PRIVATE_KEY`

---

## Databases (local SwiftData / SQLite)

**Managed by**: `AppModelContainer` in `Govorun/GovorunApp.swift`

Two `ModelConfiguration` instances in one `ModelContainer`:

| Config name | Schema | Location |
|-------------|--------|----------|
| `main` | `DictionaryEntry`, `Snippet`, `HistoryItem` | SwiftData default (`~/Library/Application Support/com.govorun.app/`) |
| `analytics` | `AnalyticsEvent` | `~/Library/Application Support/com.govorun.app/analytics.store` |

**Max rows enforced**: `HistoryStore` — 100 items; `AnalyticsService` — 10,000 events (oldest-first eviction)

**Relevant files**:
- `Govorun/Storage/HistoryStore.swift`
- `Govorun/Storage/DictionaryStore.swift`
- `Govorun/Storage/SnippetStore.swift`
- `Govorun/Services/AnalyticsService.swift`
- `Govorun/Storage/MetricsAggregator.swift`

---

## UserDefaults

**Domain**: `UserDefaults.standard`

| Key | Type | Purpose |
|-----|------|---------|
| `productMode` | String | `standard` or `super` |
| `defaultTextMode` | String | `universal`, `chat`, `email`, `document`, `note` |
| `recordingMode` | String | `pushToTalk`, `toggle`, etc. |
| `soundEnabled` | Bool | Feedback sounds |
| `saveAudioHistory` | Bool | Persist WAV files |
| `onboardingCompleted` | Bool | Skip onboarding |
| `activationKey` | String (JSON) | Encoded `ActivationKey` struct |
| `terminalPeriodEnabled` | Bool | Add trailing period in terminal |
| `llmBaseURL` | String | LLM endpoint URL |
| `llmModel` | String | LLM model alias |
| `llmRequestTimeout` | Double | LLM request timeout |
| `llmHealthcheckTimeout` | Double | LLM healthcheck timeout |
| `govorun.worker.installedVersion` | String | Installed Python worker VERSION — triggers venv rebuild |

**Relevant file**: `Govorun/Storage/SettingsStore.swift`

---

## File System Dependencies

| Path | Purpose | Created by |
|------|---------|------------|
| `~/.govorun/worker.sock` | Unix socket for ASR IPC | `worker/server.py` on startup |
| `~/.govorun/venv/` | Python virtual environment | `worker/setup.sh` |
| `~/.govorun/models/gigachat-gguf.gguf` | GigaChat GGUF model file | `SuperModelDownloadManager` |
| `~/.govorun/models/gigachat-gguf.gguf.partial` | Partial download file | `SuperModelDownloadManager` |
| `~/.govorun/models/gigachat-gguf.gguf.partial.meta` | Resume metadata JSON | `SuperModelDownloadManager` |
| `~/.cache/huggingface/hub/` | GigaAM-v3 ONNX model cache | `huggingface-hub` Python library |
| `~/Library/Application Support/com.govorun.app/` | SwiftData stores | SwiftData |
| `~/Library/Application Support/com.govorun.app/analytics.store` | Analytics SQLite | SwiftData |
| `~/Library/Application Support/com.govorun.app/AudioHistory/` | Optional WAV recordings | `AudioHistoryStorage` |
| `/tmp/govorun_<uuid>.wav` | Temporary WAV per recognition | `LocalSTTClient.saveWAVToTemp()` |

---

## macOS System Integrations

### Accessibility API (AXUIElement)

- **Purpose**: Insert transcribed text into the focused field of any app
- **Permission required**: Accessibility (prompts user in System Settings > Privacy)
- **Check**: `AXIsProcessTrusted()` in `SystemAccessibilityProvider.isTrusted()`
- **Usage**: `AXUIElementCopyAttributeValue` / `AXUIElementSetAttributeValue` for `AXValue`, `AXSelectedTextRange`, `kAXFocusedApplicationAttribute`
- **Relevant file**: `Govorun/App/AXTextInserter.swift`

### Microphone

- **Entitlement**: `com.apple.security.device.audio-input` in `Govorun/Govorun.entitlements`
- **Usage description**: `NSMicrophoneUsageDescription` in `Govorun/Info.plist`
- **Implementation**: `AVAudioEngine` tap at 16kHz PCM Int16 mono, 100ms buffers
- **Relevant file**: `Govorun/Core/AudioCapture.swift`

### Global Keyboard Monitoring

- **Purpose**: Detect activation key press/release system-wide
- **API**: `NSEvent.addGlobalMonitorForEvents(matching:)` and `addLocalMonitorForEvents(matching:)`
- **Relevant file**: `Govorun/App/NSEventMonitoring.swift`

### Clipboard (NSPasteboard)

- **Purpose**: Fallback text insertion strategy when AX fails
- **Method**: Save pasteboard → write text → simulate `Cmd+V` via `CGEvent` → restore pasteboard
- **Relevant file**: `Govorun/App/AXTextInserter.swift` (`SystemClipboardProvider`)

### Launch at Login (ServiceManagement)

- **API**: `SMAppService.mainApp.register()` / `.unregister()`
- **Relevant file**: `Govorun/Storage/SettingsStore.swift`

### NSWorkspace (Frontmost App Detection)

- **Purpose**: Determine active app to select TextMode (chat/email/document/note/universal)
- **Relevant file**: `Govorun/App/NSWorkspaceProvider.swift`, `Govorun/Core/AppContextEngine.swift`

### Menu Bar (NSStatusItem)

- **App type**: `LSUIElement = true` (no Dock icon)
- **Relevant file**: `Govorun/App/StatusBarController.swift`

---

## CI/CD External Services

| Service | Purpose | Authentication |
|---------|---------|---------------|
| GitHub Actions | CI runner (`macos-15`, `macos-14`) | — |
| GitHub Releases | DMG hosting | `RELEASE_PAT` secret |
| GitHub raw content | Appcast feed | public |
| Homebrew tap repo (`sanyasamineva0x/homebrew-govorun`) | Cask distribution | GitHub App (`HOMEBREW_APP_ID` + `HOMEBREW_APP_PRIVATE_KEY`) |

---

## What Does NOT Exist

- No cloud telemetry or analytics upload
- No authentication provider (no Apple ID, OAuth, etc.)
- No push notifications
- No CloudKit or iCloud sync
- No external LLM API calls (OpenAI, Anthropic, etc.)
- No webhooks
- No network requests during normal dictation sessions
