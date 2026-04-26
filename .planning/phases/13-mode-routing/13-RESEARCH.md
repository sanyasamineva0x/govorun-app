# Phase 13: Mode & Routing - Research

**Researched:** 2026-04-12
**Domain:** Swift enum routing, pipeline fork, guard audit, cloud client wiring in macOS app
**Confidence:** HIGH

## Summary

Phase 13 adds `ProductMode.cloud` as a third enum case and routes audio through `CloudLLMClient.processAudio()` when cloud mode is active, bypassing local STT and local LLM entirely. The core challenge is a precise audit of all `usesLLM` guard sites in AppState -- there are exactly 10 occurrences across two files -- and splitting them into `usesLocalLLM` (for llama-server/model download guards) vs keeping `usesLLM` for pipeline routing decisions that apply to both super and cloud.

The second major piece is the PipelineEngine fork: cloud mode must call `CloudLLMClient.processAudio()` directly with raw WAV audio data, skipping STT entirely. This is a fundamentally different data path from the existing STT-then-normalize flow. PipelineEngine currently holds `_llmClient: LLMClient` but has no reference to a cloud-specific client that can accept audio data. The fork must happen early in `stopRecording()` -- before the STT call.

All infrastructure is already built: CloudLLMClient (Phase 12), SberAuthService (Phase 11), CredentialStore (Phase 10), SberTrustPolicy (Phase 10). This phase is pure wiring and routing logic.

**Primary recommendation:** Add `usesLocalLLM` and `isCloud` properties to ProductMode. Replace all 5 AppState guards that trigger local LLM infrastructure with `usesLocalLLM`. Add `_cloudClient: CloudLLMClient?` to PipelineEngine with `updateCloudClient()`. Fork in `stopRecording()` before STT when `productMode.isCloud`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Ветвление внутри PipelineEngine. В начале processing flow проверяем productMode. Если .cloud -- вызываем processAudio напрямую на cloud client, пропускаем STT+LLM. Одна точка fork-а, минимальные изменения.
- **D-02:** CloudLLMClient инжектится в PipelineEngine рядом с LLMClient (через updateCloudLLMClient или аналогичный метод). PipelineEngine хранит optional ссылку на cloud client.
- **D-03:** ProductMode получает `usesLocalLLM` (true только для .superMode) и `isCloud` (true только для .cloud). `usesLLM` возвращает true для обоих (super и cloud).
- **D-04:** Все 5 guard-ов в AppState, которые триггерят локальную инфраструктуру (llama-server start, model download, LLMRuntimeManager), переключаются с `usesLLM` на `usesLocalLLM`. Cloud не запускает llama-server и не скачивает модель.
- **D-05:** Lazy creation при переключении на Cloud. `applyProductMode(.cloud)` создаёт SberAuthService + CloudLLMClient, передаёт в PipelineEngine. Когда Cloud не используется -- нет оверхеда.
- **D-06:** AppState владеет CloudLLMClient instance (stored property, optional). Пересоздаётся при каждом переключении на Cloud (credentials могли измениться).
- **D-07:** Два уровня защиты: (1) guard в `applyProductMode(.cloud)` проверяет `credentialStore.get()` -- нет credentials -> не переключается, логирует warning. (2) `@Published cloudAvailable: Bool` свойство в AppState для UI (Phase 15 использует для disable Cloud опции в picker).
- **D-08:** Пользователь вводит ключи через UI настроек (Phase 15), приложение сохраняет в Keychain через CredentialStore. Проверка credentials -- через CredentialStore.get().

### Claude's Discretion
- Конкретная реализация ветвления в PipelineEngine (новый метод processCloudAudio vs if/switch в существующем flow)
- Naming: updateCloudLLMClient vs setCloudClient vs другое
- Нужен ли отдельный протокол для audio-in path (CloudAudioProcessing) или достаточно конкретного типа
- ProductMode.title для .cloud ("Говорун Cloud" vs "Cloud")

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MODE-01 | ProductMode.cloud -- третий enum case рядом с standard и superMode | ProductMode.swift analysis: add `.cloud` case, `usesLocalLLM`, `isCloud` properties. Codable rawValue "cloud" auto-works. |
| MODE-02 | Cloud маршрутизирует аудио в облако, минуя локальный STT и LLM | PipelineEngine fork pattern: early branch in `stopRecording()` before STT call at line 357. Cloud path calls `processAudio()` directly. |
| MODE-03 | Standard и Super режимы продолжают работать без изменений | Guard audit identifies exactly which `usesLLM` sites to change to `usesLocalLLM`. PipelineEngine existing paths untouched when not `.cloud`. |
| MODE-04 | Cloud режим доступен только при наличии credentials в Keychain | CredentialStore.get() check in `applyProductMode(.cloud)`. `@Published cloudAvailable` for UI gating. |
| CLOUD-04 | Локальный STT (GigaAM) не используется в Cloud режиме | PipelineEngine cloud fork skips `sttClient.recognize()` entirely. Audio data goes directly to CloudLLMClient.processAudio(). |
</phase_requirements>

## Architecture Patterns

### Complete usesLLM Guard Audit

Exhaustive search of `usesLLM` in AppState.swift reveals **10 occurrences** across **8 distinct guard sites**. Each must be classified as "change to usesLocalLLM" or "keep as usesLLM". [VERIFIED: codebase grep]

| # | Line | Current Code | Purpose | Action |
|---|------|-------------|---------|--------|
| G1 | 167 | `settings.productMode.usesLLM ? .standard : settings.productMode` | Init: set pipeline to .standard until super assets checked | CHANGE to `usesLocalLLM` -- cloud does not need super assets check |
| G2 | 193 | `settings.productMode.usesLLM ? .notStarted : .disabled` | Init: llmRuntimeState initial value | CHANGE to `usesLocalLLM` -- cloud does not use llmRuntimeManager |
| G3 | 270 | `settings.productMode.usesLLM ? initialLLMRuntimeState : .disabled` | Test init: llmRuntimeState | CHANGE to `usesLocalLLM` |
| G4 | 271 | `settings.productMode.usesLLM ? .standard : settings.productMode` | Test init: pipeline productMode | CHANGE to `usesLocalLLM` |
| G5 | 297 | `currentProductMode.usesLLM ? state : .disabled` | updateLLMRuntimeState helper | CHANGE to `usesLocalLLM` -- cloud should not drive llmRuntimeState |
| G6 | 356 | `effectiveProductMode.usesLLM` | handleSuperAssetsChanged guard | CHANGE to `usesLocalLLM` -- cloud does not depend on super assets |
| G7 | 432 | `currentProductMode.usesLLM` | start(): trigger handleSuperAssetsChanged | CHANGE to `usesLocalLLM` -- cloud should not trigger super assets flow |
| G8 | 647 | `productMode.usesLLM` | applyProductMode: trigger handleSuperAssetsChanged | CHANGE to `usesLocalLLM` -- cloud has its own wiring path |
| G9 | 667 | `currentProductMode.usesLLM` | applyLLMConfiguration: restart if LLM mode | CHANGE to `usesLocalLLM` -- LLM config is local llama-server only |
| G10 | 839 | `currentProductMode.usesLLM && superAssetsState != .installed` | handleActivated: downgrade to standard if assets missing | CHANGE to `usesLocalLLM` -- cloud does not need super assets |

**Additionally in PipelineEngine.swift** (2 occurrences): [VERIFIED: codebase grep]

| # | Line | Current Code | Purpose | Action |
|---|------|-------------|---------|--------|
| P1 | 431 | `!currentProductMode.usesLLM` | Embedded snippet: skip LLM if no LLM mode | KEEP `usesLLM` -- cloud also uses LLM for embedded snippets (via normalize path) |
| P2 | 562 | `!currentProductMode.usesLLM` | Trivial text gate: skip LLM if standard mode | KEEP `usesLLM` -- cloud also routes to LLM (but via different mechanism for cloud fork) |

**Additional site in AppState (analytics):**

| # | Line | Current Code | Purpose | Action |
|---|------|-------------|---------|--------|
| A1 | 863 | `pipelineEngine.productMode.usesLLM` | Add styleSelectionMode to analytics | KEEP `usesLLM` -- cloud also uses styles |

**Summary:** All 10 AppState guards (G1-G10) change to `usesLocalLLM`. PipelineEngine guards (P1, P2) and analytics (A1) keep `usesLLM`. However, P1 and P2 behavior for cloud requires special attention -- see Pattern 2 below.

### Pattern 1: ProductMode Extension

```swift
// Models/ProductMode.swift
enum ProductMode: String, CaseIterable, Codable {
    case standard
    case superMode = "super"
    case cloud

    var usesLLM: Bool {
        self == .superMode || self == .cloud
    }

    var usesLocalLLM: Bool {
        self == .superMode
    }

    var isCloud: Bool {
        self == .cloud
    }

    var title: String {
        switch self {
        case .standard: "Говорун"
        case .superMode: "Говорун Super"
        case .cloud: "Говорун Cloud"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            "Быстрый голосовой ввод без ИИ-обработки"
        case .superMode:
            "Голосовой ввод с ИИ-усилением"
        case .cloud:
            "Голосовой ввод через GigaChat Max"
        }
    }
}
```

[VERIFIED: ProductMode.swift at line 1-30 is the complete current file]

**Codable safety:** rawValue "cloud" is new, never persisted before. Old UserDefaults with "standard" or "super" decode fine. If user had .cloud persisted and removes credentials, `applyProductMode` guard prevents activation. [VERIFIED: SettingsStore uses Codable rawValue]

### Pattern 2: PipelineEngine Cloud Fork

Per D-01 and D-02: PipelineEngine stores an optional reference to CloudLLMClient. The fork happens inside `stopRecording()` before the STT call. [VERIFIED: D-01, D-02 in CONTEXT.md]

**Recommendation:** Implement as a separate private method `processCloudPath()` called from `stopRecording()`. This avoids nesting cloud logic inside the existing function and keeps the standard/super path completely untouched.

```swift
// PipelineEngine additions
private var _cloudClient: CloudLLMClient?  // stored under lock

func updateCloudClient(_ client: CloudLLMClient?) {
    lock.lock()
    defer { lock.unlock() }
    _cloudClient = client
}

func stopRecording() async throws -> PipelineResult {
    let stopTime = CFAbsoluteTimeGetCurrent()
    let sessionId = snapshotSessionId()
    let (currentProductMode, currentSuperStyle, currentHints, currentLLMClient) = snapshotConfig()

    // Cloud fork -- before STT
    if currentProductMode.isCloud {
        return try await processCloudPath(
            stopTime: stopTime,
            sessionId: sessionId,
            superStyle: currentSuperStyle,
            hints: currentHints
        )
    }

    // ... existing STT -> normalize flow unchanged ...
}
```

**Cloud path data flow:**
1. `markRecordingStopped()` + `audioCapture.stopRecording()` -- get raw WAV data
2. Save audio to history if enabled
3. Cancellation check
4. `cloudClient.processAudio(audioData:superStyle:hints:)` -- single API call does STT+normalization
5. Post-processing: `ListFormatter.format()`, terminal period, style caps
6. Return PipelineResult with new `.cloud` normalization path

**Key point about P1/P2 guards:** When `productMode.isCloud`, the cloud fork happens BEFORE lines 431 and 562. Those guards are never reached for cloud mode. So keeping `usesLLM` there is correct -- they only execute for standard and super modes.

### Pattern 3: snapshotConfig Extension

`snapshotConfig()` currently returns `(ProductMode, SuperTextStyle?, NormalizationHints, LLMClient)`. It must also snapshot `_cloudClient` to avoid race conditions during mode switches. [VERIFIED: PipelineEngine.swift line 676-679]

```swift
// Extended snapshot -- add cloudClient
private func snapshotConfig() -> (ProductMode, SuperTextStyle?, NormalizationHints, LLMClient, CloudLLMClient?) {
    lock.lock()
    defer { lock.unlock() }
    return (_productMode, _superStyle, _hints, _llmClient, _cloudClient)
}
```

### Pattern 4: AppState Cloud Wiring in applyProductMode

Per D-05 and D-06: lazy creation of CloudLLMClient on each switch to cloud mode. [VERIFIED: D-05, D-06 in CONTEXT.md]

```swift
private func applyProductMode(_ productMode: ProductMode) {
    currentProductMode = productMode
    pendingProductMode = nil

    switch productMode {
    case .standard:
        pipelineEngine.productMode = productMode
        pipelineEngine.updateCloudClient(nil)
        llmRuntimeManager?.stop()
        updateLLMRuntimeState(.disabled)

    case .superMode:
        pipelineEngine.updateCloudClient(nil)
        guard let llmRuntimeManager else {
            pipelineEngine.productMode = productMode
            return
        }
        if isReady {
            Task { await handleSuperAssetsChanged() }
        } else {
            updateLLMRuntimeState(.notStarted)
        }

    case .cloud:
        guard let credentials = credentialStore.get() else {
            Self.logger.warning("Cloud credentials не найдены, остаёмся на текущем режиме")
            return
        }
        let authService = SberAuthService(
            credentialProvider: { [credentialStore] in credentialStore.get() }
        )
        let httpClient = trustPolicy?.urlSession ?? URLSession.shared
        let cloudClient = CloudLLMClient(
            authService: authService,
            httpClient: httpClient
        )
        self.cloudLLMClient = cloudClient
        pipelineEngine.updateCloudClient(cloudClient)
        pipelineEngine.updateLLMClient(cloudClient) // for embedded snippet path
        pipelineEngine.productMode = .cloud
        llmRuntimeManager?.stop()
        updateLLMRuntimeState(.disabled)
    }
}
```

**Critical subtlety:** `pipelineEngine.updateLLMClient(cloudClient)` must ALSO be called for `.cloud`. Reason: the embedded snippet path at line 431/477 calls `currentLLMClient.normalize()`. When in cloud mode with embedded snippets, this should call CloudLLMClient.normalize() (the text path, not processAudio). Without this, embedded snippets in cloud mode would use the OLD LLMClient (LocalLLMClient or PlaceholderLLMClient). [VERIFIED: PipelineEngine lines 431-478, CloudLLMClient conforms to LLMClient]

### Pattern 5: NormalizationPath.cloud

PipelineResult.NormalizationPath needs a new `.cloud` case for analytics segmentation. [VERIFIED: PipelineEngine.swift lines 45-53]

```swift
enum NormalizationPath: String {
    case trivial
    case snippet
    case snippetPlusLLM
    case llm
    case llmRejected
    case llmFailed
    case cloud        // new: audio went through CloudLLMClient.processAudio
    case cloudFailed  // new: cloud failed, deterministic fallback
}
```

### Pattern 6: handleActivated Cloud Style Resolution

Line 839-849 in AppState.handleActivated sets effectiveProductMode and superStyle. Cloud mode needs its own handling. [VERIFIED: AppState.swift lines 839-849]

```swift
// In handleActivated:
let effectiveProductMode: ProductMode
if currentProductMode.usesLocalLLM, superAssetsState != .installed {
    effectiveProductMode = .standard  // downgrade super if assets missing
} else {
    effectiveProductMode = currentProductMode  // cloud and standard pass through
}
pipelineEngine.productMode = effectiveProductMode

// Cloud also uses styles for the system prompt
pipelineEngine.superStyle = effectiveProductMode.usesLLM
    ? SuperStyleEngine.resolve(
        bundleId: context.bundleId,
        mode: settings.superStyleMode,
        manualStyle: settings.manualSuperStyle
    )
    : nil
```

**Key insight:** `superStyle` must be set for cloud mode too, not just superMode. CloudLLMClient.processAudio uses `superStyle.systemPrompt()` for the system message. Currently the guard is `effectiveProductMode == .superMode` which would leave superStyle nil for cloud. Change to `effectiveProductMode.usesLLM`. [VERIFIED: CloudLLMClient.swift line 112, AppState.swift line 843]

### Pattern 7: cloudAvailable Published Property (MODE-04)

Per D-07: AppState exposes `@Published cloudAvailable: Bool` for UI gating. [VERIFIED: D-07 in CONTEXT.md]

```swift
// AppState
@Published var cloudAvailable: Bool = false

// Updated whenever credentials change
private func refreshCloudAvailability() {
    cloudAvailable = credentialStore.get() != nil
}
```

Call `refreshCloudAvailability()` in: `init`, `start()`, and when CredentialStore changes (Phase 15 will trigger this via settings UI). For Phase 13, init + start is sufficient.

### Recommended Project Structure Changes

```
Govorun/
├── Models/
│   └── ProductMode.swift           # ADD .cloud case, usesLocalLLM, isCloud
├── Core/
│   └── PipelineEngine.swift        # ADD _cloudClient, updateCloudClient(), processCloudPath()
├── App/
│   └── AppState.swift              # MODIFY applyProductMode, all 10 usesLLM guards,
│                                   #   ADD cloudLLMClient property, cloudAvailable,
│                                   #   ADD credentialStore property, trustPolicy property
├── Services/
│   └── CloudLLMClient.swift        # EXISTING (Phase 12) -- no changes
│   └── SberAuthService.swift       # EXISTING (Phase 11) -- no changes
│   └── SberTrustPolicy.swift       # EXISTING (Phase 10) -- no changes
│   └── HTTPClient.swift            # EXISTING (Phase 10) -- no changes
└── Storage/
    └── CredentialStore.swift        # EXISTING (Phase 10) -- no changes
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cloud audio processing | Custom audio encode/upload/chat | CloudLLMClient.processAudio() | Phase 12 already implements the two-step flow (upload WAV + chat/completions) |
| OAuth token management | Token fetch in AppState | SberAuthService via credentialProvider closure | Phase 11 built actor-based auth with coalesced refresh |
| TLS certificate trust | Manual SecTrust in AppState | SberTrustPolicy.urlSession | Phase 10 built the trust delegate |
| Keychain access | Raw Security.framework calls | CredentialStore.get() | Phase 10 built the wrapper with protocol |
| Mode persistence | Custom UserDefaults code | SettingsStore.productMode (Codable) | Already persists ProductMode rawValue, "cloud" auto-works |

## Common Pitfalls

### Pitfall 1: Forgetting to Set superStyle for Cloud Mode
**What goes wrong:** CloudLLMClient.processAudio uses superStyle.systemPrompt(). If superStyle is nil (because handleActivated only sets it for .superMode), cloud gets no style-aware prompt.
**Why it happens:** Line 843 currently guards `effectiveProductMode == .superMode`. Cloud is excluded.
**How to avoid:** Change guard to `effectiveProductMode.usesLLM` so both super and cloud get style resolution.
**Warning signs:** Cloud output ignores formal/relaxed context. All cloud output is "normal" style regardless of app.

### Pitfall 2: Embedded Snippets in Cloud Mode Use Wrong LLMClient
**What goes wrong:** PipelineEngine line 477 calls `currentLLMClient.normalize()` for embedded snippets. If `_llmClient` was not updated when switching to cloud, it still holds LocalLLMClient (or PlaceholderLLMClient), which fails.
**Why it happens:** D-02 says "inject CloudLLMClient рядом с LLMClient" -- it is easy to forget that `updateLLMClient()` must ALSO be called for the text path.
**How to avoid:** In `applyProductMode(.cloud)`, call BOTH `updateCloudClient(cloudClient)` AND `updateLLMClient(cloudClient)`. CloudLLMClient conforms to LLMClient so this works.
**Warning signs:** Embedded snippets crash or timeout in cloud mode while standalone snippets work fine.

### Pitfall 3: Cloud Fork Does Not Skip STT
**What goes wrong:** If the cloud fork is placed after the STT call, cloud mode still tries to recognize speech locally. The Python worker must be running, audio goes through GigaAM, and the result is discarded.
**Why it happens:** Natural tendency to add the fork after existing code rather than before it.
**How to avoid:** Place cloud fork as the FIRST branching point in `stopRecording()`, right after `snapshotConfig()`. Before `audioCapture.stopRecording()` and before `sttClient.recognize()`. Actually: must be after `audioCapture.stopRecording()` (need the audio data) but before `sttClient.recognize()`.
**Warning signs:** Cloud mode requires Python worker to be running. Cloud dictation latency includes unnecessary STT time.

### Pitfall 4: Missing Cancellation Handling in Cloud Path
**What goes wrong:** User presses Esc during cloud dictation. If processCloudPath does not check `currentIsCancelled()`, the request completes and text is inserted even after cancel.
**Why it happens:** New code path, cancellation checks must be explicitly added.
**How to avoid:** Check `currentIsCancelled()` before and after the `processAudio` call, same pattern as existing LLM path.
**Warning signs:** Pressing Esc during cloud dictation still inserts text.

### Pitfall 5: Race Between Mode Switch and Active Recording
**What goes wrong:** User starts dictation in super mode, then settings change triggers mode switch to cloud. `snapshotConfig()` already captured the old mode, so the in-flight recording is safe. But `_cloudClient` could be set while `_llmClient` is still the old LocalLLMClient.
**Why it happens:** Mode switch is not gated on pipeline idle state.
**How to avoid:** PipelineEngine already snapshots all state under lock at the start of `stopRecording()`. The snapshot includes `_cloudClient`. As long as snapshot captures both clients atomically (same lock), the race is safe. The CONTEXT.md pattern of pending/apply already handles this -- `applyPendingSettings` only runs when pipeline is idle.
**Warning signs:** No real warning signs -- the existing pending/apply pattern handles this correctly.

### Pitfall 6: applyProductMode(.cloud) Silently Fails Without Feedback
**What goes wrong:** D-07 says guard credentials, log warning, do not switch. But the user sees no feedback -- mode picker still shows the old mode, no error message.
**Why it happens:** Phase 13 only adds the guard. Phase 15 adds the UI feedback.
**How to avoid:** For Phase 13, ensure `pendingProductMode` is cleared even when guard fails (otherwise it stays pending and retries infinitely). Log at warning level. Phase 15 will use `cloudAvailable` to disable the picker option.
**Warning signs:** ProductMode picker shows cloud selected but behavior is not cloud. Or pendingProductMode keeps trying to apply cloud.

## Code Examples

### Cloud processCloudPath Implementation

```swift
// Source: derived from existing stopRecording() pattern + CloudLLMClient.processAudio API
private func processCloudPath(
    stopTime: CFAbsoluteTime,
    sessionId: UUID,
    superStyle: SuperTextStyle?,
    hints: NormalizationHints
) async throws -> PipelineResult {
    let effectiveTerminalPeriod = superStyle?.terminalPeriod ?? terminalPeriodEnabled

    func applyPostProcessing(_ text: String) -> String {
        let periodText = effectiveTerminalPeriod
            ? text
            : DeterministicNormalizer.stripTrailingPeriods(text)
        let styledText = superStyle?.applyDeterministic(periodText) ?? periodText
        return ListFormatter.format(styledText, style: superStyle)
    }

    markRecordingStopped()
    let audioDurationMs = Int(audioCapture.duration * 1_000)
    let audioData = audioCapture.stopRecording()

    // Аудио для истории
    let audioFileName: String?
    if !audioData.isEmpty, saveAudioHistory {
        do {
            audioFileName = try saveAudioFile(audioData, sessionId)
        } catch {
            Self.logger.error("Failed to save audio history: \(String(describing: error), privacy: .public)")
            audioFileName = nil
        }
    } else {
        audioFileName = nil
    }

    func cleanupAudioOnFailure() {
        if let audioFileName { deleteAudioFile(audioFileName) }
    }

    guard !audioData.isEmpty else {
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
        return PipelineResult(
            sessionId: sessionId, rawTranscript: "", normalizedText: "",
            superStyle: superStyle, normalizationPath: .trivial,
            sttLatencyMs: 0, llmLatencyMs: 0, insertionLatencyMs: 0,
            totalLatencyMs: totalMs, audioDurationMs: audioDurationMs, audioFileName: audioFileName
        )
    }

    guard !currentIsCancelled() else {
        cleanupAudioOnFailure()
        throw PipelineError.cancelled
    }

    // Snapshot cloud client
    let cloudClient: CloudLLMClient
    do {
        lock.lock()
        guard let client = _cloudClient else {
            lock.unlock()
            throw LLMError.networkError("Cloud client не настроен")
        }
        cloudClient = client
        lock.unlock()
    }

    let llmStart = CFAbsoluteTimeGetCurrent()
    let cloudOutput: String

    do {
        cloudOutput = try await cloudClient.processAudio(
            audioData: audioData,
            superStyle: superStyle ?? .normal,
            hints: hints
        )
        guard !currentIsCancelled() else {
            cleanupAudioOnFailure()
            throw PipelineError.cancelled
        }
    } catch is CancellationError {
        cleanupAudioOnFailure()
        throw PipelineError.cancelled
    } catch {
        // Graceful degradation не применима к cloud: нет rawTranscript для fallback
        let llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)
        Self.logger.error("Cloud failed: \(String(describing: error), privacy: .public)")
        cleanupAudioOnFailure()
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
        return PipelineResult(
            sessionId: sessionId, rawTranscript: "", normalizedText: "",
            superStyle: superStyle, normalizationPath: .cloudFailed,
            sttLatencyMs: 0, llmLatencyMs: llmLatencyMs, insertionLatencyMs: 0,
            totalLatencyMs: totalMs, audioDurationMs: audioDurationMs, audioFileName: audioFileName
        )
    }

    let llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)
    let finalText = applyPostProcessing(cloudOutput)
    let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)

    return PipelineResult(
        sessionId: sessionId, rawTranscript: cloudOutput, normalizedText: finalText,
        superStyle: superStyle, normalizationPath: .cloud,
        sttLatencyMs: 0, llmLatencyMs: llmLatencyMs, insertionLatencyMs: 0,
        totalLatencyMs: totalMs, audioDurationMs: audioDurationMs, audioFileName: audioFileName
    )
}
```

**Critical note on error handling:** Unlike super mode, cloud mode has NO deterministic fallback when the API fails. There is no rawTranscript (STT was skipped). The only option is to return empty text and log the error. This is a fundamental difference from the super mode graceful degradation pattern. [VERIFIED: no STT in cloud path per CLOUD-04]

### AppState.init Cloud Additions

```swift
// New stored properties in AppState
private var cloudLLMClient: CloudLLMClient?
private let credentialStore: CredentialStoring
private let trustPolicy: TrustPolicyProviding?
@Published var cloudAvailable: Bool = false
```

### CredentialStore Injection in AppState

Production init creates a real CredentialStore. Test init receives a mock. [VERIFIED: AppState.swift lines 109-200 for production init, lines 210-288 for test init]

```swift
// Production init addition:
let credentialStore = CredentialStore()
self.credentialStore = credentialStore
let trustPolicy: TrustPolicyProviding?
do {
    trustPolicy = try SberTrustPolicy()
} catch {
    Self.logger.error("SberTrustPolicy не инициализировалась: \(String(describing: error), privacy: .public)")
    trustPolicy = nil
}
self.trustPolicy = trustPolicy
cloudAvailable = credentialStore.get() != nil

// Test init addition:
self.credentialStore = credentialStore ?? MockCredentialStore()
self.trustPolicy = nil
cloudAvailable = self.credentialStore.get() != nil
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `usesLLM` gates all LLM logic | `usesLocalLLM` for local infra, `usesLLM` for pipeline routing | Phase 13 | 10 guard sites in AppState change |
| Single `_llmClient` in PipelineEngine | `_llmClient` + `_cloudClient` | Phase 13 | Cloud audio fork possible |
| Two product modes | Three product modes | Phase 13 | All switch statements on ProductMode need .cloud case |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Cloud error path returns empty text (no deterministic fallback) | Code Examples | If users expect some text on failure, UX is surprising. But there is genuinely no transcript available. |
| A2 | NormalizationGate is NOT applied to cloud processAudio output | Architecture Patterns | CONTEXT.md says cloud output goes through post-processing but does not mention gate. Phase 14 (NormalizationGate) may add gate for cloud. For Phase 13, skip gate -- processAudio output is already normalized by GigaChat. |
| A3 | Snippets are NOT matched in cloud mode processAudio path | Architecture Patterns | No rawTranscript to match against. Standalone/embedded snippet detection requires STT output. Cloud mode skips snippets entirely for now. |

## Open Questions

1. **Should NormalizationGate evaluate cloud processAudio output?**
   - What we know: Cloud processAudio returns fully normalized text (STT + normalization in one step). Gate was designed for local LLM output quality control.
   - What's unclear: Should gate reject cloud output too? Cloud model quality may differ from local.
   - Recommendation: Skip gate for Phase 13 cloud path. Phase 14 (NormalizationGate integration for cloud) can add it if needed. The CONTEXT.md does not mention gate for the cloud fork.

2. **Should cloud mode support snippet matching?**
   - What we know: Snippets match on STT transcript text. Cloud mode has no STT transcript -- audio goes directly to API.
   - What's unclear: Can snippet triggers be injected into the cloud system prompt instead?
   - Recommendation: No snippet support in cloud processAudio path for Phase 13. REQUIREMENTS.md CLOUD-05 assigns snippets to Phase 14, and it says "SnippetEngine.match на output" -- matching on cloud OUTPUT, not input. Phase 14 will handle this.

3. **What happens when user persists .cloud mode, removes credentials, then restarts?**
   - What we know: SettingsStore.productMode will return .cloud on restart. applyProductMode(.cloud) will fail the credential guard.
   - What's unclear: Should the app auto-downgrade to .standard? Or leave the mode as cloud and fail each dictation?
   - Recommendation: In `start()`, check if currentProductMode is .cloud and credentials are missing. If so, reset to .standard. Log a warning. This prevents dead-mode-on-restart.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (986+ tests) |
| Config file | Govorun.xctestplan |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MODE-01 | ProductMode.cloud is third case with usesLLM=true, usesLocalLLM=false, isCloud=true | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/ProductModeTests` | Wave 0 (new file) |
| MODE-02 | Cloud mode routes audio to processAudio, skips STT | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/PipelineEngineTests` | Existing (add new tests) |
| MODE-03 | Standard/Super modes unchanged | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/PipelineEngineTests` | Existing (regression) |
| MODE-04 | Cloud blocked without credentials | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/AppStateModeTests` | Wave 0 (new file or extend IntegrationTests) |
| CLOUD-04 | STT not called in cloud mode | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/PipelineEngineTests` | Existing (add assertion: sttClient.recognizeCalls == 0) |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `GovorunTests/ProductModeTests.swift` -- covers MODE-01 (new: usesLocalLLM, isCloud properties)
- [ ] New test methods in `GovorunTests/PipelineEngineTests.swift` -- covers MODE-02, MODE-03, CLOUD-04
- [ ] New test methods for AppState cloud wiring -- covers MODE-04

## Project Constraints (from CLAUDE.md)

- Swift 5.10+, macOS 14.0+, Apple Silicon only [VERIFIED: CLAUDE.md]
- Core/ does NOT import SwiftUI or AppKit [VERIFIED: CLAUDE.md]
- Services/ does NOT import AppKit [VERIFIED: CLAUDE.md]
- TDD: test (red) -> code (green) -> refactor [VERIFIED: CLAUDE.md]
- All services through protocols (LLMClient, CredentialStoring, AuthService, etc.) [VERIFIED: CLAUDE.md]
- Mocks in tests, never real Python worker or models [VERIFIED: CLAUDE.md]
- Typed errors: `enum XxxError: Error, LocalizedError` [VERIFIED: CLAUDE.md]
- async/await, not completion handlers [VERIFIED: CLAUDE.md]
- @MainActor only for UI code [VERIFIED: CLAUDE.md]
- No force unwrap (!) in production code [VERIFIED: CLAUDE.md]
- Commits in Russian, no Co-Authored-By [VERIFIED: CLAUDE.md]
- `SWIFT_STRICT_CONCURRENCY: complete` [VERIFIED: CLAUDE.md]
- XcodeGen: `xcodegen generate` after file changes to project.yml [VERIFIED: CLAUDE.md]

## Sources

### Primary (HIGH confidence)
- `Govorun/Models/ProductMode.swift` -- current enum (2 cases, usesLLM for superMode only)
- `Govorun/Core/PipelineEngine.swift` -- full processing flow, snapshotConfig, updateLLMClient
- `Govorun/App/AppState.swift` -- all 10 usesLLM guard sites, applyProductMode, handleActivated
- `Govorun/Services/CloudLLMClient.swift` -- processAudio method signature and implementation
- `Govorun/Services/SberAuthService.swift` -- actor-based auth with credentialProvider closure
- `Govorun/Storage/CredentialStore.swift` -- CredentialStoring protocol, get() returns optional tuple
- `.planning/phases/13-mode-routing/13-CONTEXT.md` -- all locked decisions D-01 through D-08
- `.planning/research/ARCHITECTURE.md` -- system overview, ProductMode.cloud sketch, AppState changes
- `.planning/research/PITFALLS.md` -- usesLLM routing pitfall, pipeline swap race, gate rejection

### Secondary (MEDIUM confidence)
- `.planning/research/FEATURES.md` -- feature landscape, integration points
- `GovorunTests/PipelineEngineTests.swift` -- existing test patterns, mock helpers

## Metadata

**Confidence breakdown:**
- ProductMode changes: HIGH -- simple enum extension, verified against current code
- Guard audit: HIGH -- exhaustive grep, each site analyzed with line numbers
- PipelineEngine fork: HIGH -- verified CloudLLMClient.processAudio exists with exact signature
- AppState wiring: HIGH -- all dependencies (SberAuthService, CredentialStore, SberTrustPolicy) verified as built
- Error handling: MEDIUM -- cloud-failure-returns-empty-text is a design choice that needs validation

**Research date:** 2026-04-12
**Valid until:** 2026-05-12 (stable -- no external dependencies changing)
