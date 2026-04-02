# Phase 3: Pipeline Integration - Research

**Researched:** 2026-03-30
**Domain:** Swift protocol refactoring -- replacing TextMode with SuperTextStyle in LLM pipeline
**Confidence:** HIGH

## Summary

Phase 3 is a mechanical signature migration: replace TextMode with SuperTextStyle across the LLM pipeline chain. The change surface is well-bounded -- 6 production files and 5 test files. The code is already fully read and understood.

The key insight: SuperTextStyle already has all the APIs that TextMode provides (systemPrompt(), contract, styleBlock, applyDeterministic). The migration is a direct 1:1 replacement at every call site. No new logic is needed, only signature changes and wiring.

The riskiest part is the PipelineEngine with 21 occurrences of textMode/TextMode across the file -- the snapshotConfig() return tuple changes, every PipelineResult creation changes, and both NormalizationGate.evaluate() call sites need the contract bridge (D-04). Compiler will catch all mismatches -- zero runtime ambiguity.

**Primary recommendation:** Work top-down through the protocol chain: LLMClient protocol -> LocalLLMClient/PlaceholderLLMClient -> PipelineEngine (stored property + snapshotConfig + all PipelineResult sites) -> NormalizationPipeline.postflight -> consumers (AppState, HistoryStore, AnalyticsEvent) -> tests. Compiler errors guide each step.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Hardcode `.auto` + `.normal` -- AppState calls `SuperStyleEngine.resolve(bundleId: context.bundleId, mode: .auto, manualStyle: .normal)` and passes result to PipelineEngine. Phase 6 replaces hardcode with real SettingsStore values. Do NOT create TextMode-to-SuperTextStyle bridge.
- **D-02:** Full replacement textMode->superStyle in PipelineEngine in one go. Delete `_textMode` property, replace with `_superStyle: SuperTextStyle?`. All 30+ textMode references updated. snapshotConfig() returns SuperTextStyle instead of TextMode.
- **D-03:** `PipelineResult.superStyle: SuperTextStyle?` fully replaces `textMode: TextMode`. Do NOT add both fields simultaneously. All consumers updated in Phase 3: AppState.handlePipelineResult(), HistoryStore.save(), AnalyticsService.
- **D-04:** Replace `currentTextMode.llmOutputContract` -> `currentSuperStyle?.contract ?? .normalization` in NormalizationGate.evaluate() calls. Gate signature does NOT change (that is Phase 4). Result is the same (.normalization) but path goes through SuperTextStyle.
- **D-05:** Single signature `normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String`. Old signature with `mode: TextMode` deleted completely (PIPE-01). PlaceholderLLMClient also updated.

### Claude's Discretion
- Order of file updates (LLMClient -> LocalLLMClient -> PipelineEngine -> PipelineResult consumers -> Tests)
- Handling nil superStyle in PipelineResult (optional vs default .normal)
- Parameter names in snapshotConfig() -- `currentSuperStyle` vs `currentStyle`

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PIPE-01 | LLMClient.normalize(_:superStyle:hints:) -- single signature, not overload | LLMClient protocol has exactly one method `normalize(_:mode:hints:)` -> direct rename. MockLLMClient, PlaceholderLLMClient, LocalLLMClient all conform. |
| PIPE-02 | LocalLLMClient uses SuperTextStyle.systemPrompt() for LLM request | LocalLLMClient.sendChatCompletion() currently calls `mode.systemPrompt(...)`. SuperTextStyle has identical systemPrompt() signature -- direct replacement. |
| PIPE-03 | PipelineEngine stores _superStyle: SuperTextStyle? instead of _textMode | PipelineEngine has `_textMode: TextMode = .universal` with NSLock-guarded computed property. 21 occurrences of textMode/TextMode in file. snapshotConfig() returns tuple including TextMode. |
| PIPE-04 | PipelineResult.superStyle: SuperTextStyle? instead of textMode: TextMode | PipelineResult has `textMode: TextMode` field, used in init and 9 PipelineResult(...) construction sites within PipelineEngine. HistoryStore.save() reads `result.textMode.rawValue`. |
| TEST-06 | Migrate existing tests: MockLLMClient, AppContextEngineTests, HistoryStoreTests, SnippetEngineTests | MockLLMClient.normalizeCalls tuple has `mode: TextMode`. AppContextEngineTests tests TextMode-specific prompts. HistoryStoreTests builds PipelineResult with textMode. SnippetEngineTests has TextModeSnippetPromptTests class. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **No Co-Authored-By** -- public repo, no AI signs
- **Commits in Russian** -- `feat: ...`, `fix: ...`
- **TDD** -- test (red) -> code (green) -> refactor
- **All services through protocols** (LLMClient protocol pattern)
- **Mocks in tests**, never real Python worker or models
- **async/await**, not completion handlers
- **@MainActor only for UI code**
- **No force unwrap (!)** in production code
- **Core/ does NOT import SwiftUI or AppKit**
- **Models/ -- pure value types**
- **NSLock for thread-safe mutable state** in non-actor types
- **Swift strict concurrency: complete**

## Architecture Patterns

### Change Propagation Chain

The refactoring follows a strict dependency chain. Each step enables the next:

```
1. LLMClient.swift        -- protocol signature
2. LocalLLMClient.swift    -- real implementation
   PlaceholderLLMClient    -- (in LLMClient.swift, line 207)
3. PipelineEngine.swift    -- stored property, snapshotConfig, all PipelineResult sites
4. NormalizationPipeline   -- postflight() textMode param -> bridge via superStyle.contract
5. AppState.swift          -- wiring: pipelineEngine.textMode -> pipelineEngine.superStyle
6. HistoryStore.swift      -- result.textMode.rawValue -> result.superStyle?.rawValue ?? "none"
7. AnalyticsEvent.swift    -- metadata key (string only, stays "text_mode" or changes)
8. Tests                   -- MockLLMClient, AppContextEngineTests, HistoryStoreTests, SnippetEngineTests
```

### Existing Concurrency Pattern (must preserve)

PipelineEngine uses `NSLock` + private stored properties with public computed wrappers:

```swift
// Current pattern -- replicate for superStyle
private var _textMode: TextMode = .universal

var textMode: TextMode {
    get { lock.lock(); defer { lock.unlock() }; return _textMode }
    set { lock.lock(); defer { lock.unlock() }; _textMode = newValue }
}
```

Becomes:
```swift
private var _superStyle: SuperTextStyle? = nil

var superStyle: SuperTextStyle? {
    get { lock.lock(); defer { lock.unlock() }; return _superStyle }
    set { lock.lock(); defer { lock.unlock() }; _superStyle = newValue }
}
```

### snapshotConfig() Tuple Change

Current:
```swift
private func snapshotConfig() -> (ProductMode, TextMode, NormalizationHints, LLMClient) {
    lock.lock()
    defer { lock.unlock() }
    return (_productMode, _textMode, _hints, _llmClient)
}
```

New:
```swift
private func snapshotConfig() -> (ProductMode, SuperTextStyle?, NormalizationHints, LLMClient) {
    lock.lock()
    defer { lock.unlock() }
    return (_productMode, _superStyle, _hints, _llmClient)
}
```

The destructured variable in stopRecording() changes from `currentTextMode` to `currentSuperStyle`.

### NormalizationGate Bridge (D-04)

Two call sites in PipelineEngine use `currentTextMode.llmOutputContract`:

1. **Line 480 (embedded snippet path):**
```swift
// Before
contract: currentTextMode.llmOutputContract
// After
contract: currentSuperStyle?.contract ?? .normalization
```

2. **NormalizationPipeline.postflight (line 621):**
The postflight function itself takes `textMode: TextMode` and calls `textMode.llmOutputContract`. This needs to change to accept `superStyle: SuperTextStyle?` (or accept the contract directly). The simplest approach matching D-04: pass `currentSuperStyle?.contract ?? .normalization` directly as the `contract` parameter, changing postflight's signature from `textMode: TextMode` to `contract: LLMOutputContract`.

### AppState Wiring (D-01)

Current (handleActivated, line 841):
```swift
pipelineEngine.textMode = context.textMode
```

New:
```swift
let superStyle = SuperStyleEngine.resolve(
    bundleId: context.bundleId,
    mode: .auto,
    manualStyle: .normal
)
pipelineEngine.superStyle = superStyle
```

Note: `context.textMode` is still used for analytics metadata (line 856). TextMode in AppContext remains -- it is deleted in Phase 9 (DELETE-03). Phase 3 only replaces the pipeline path.

### PipelineResult Construction Pattern

9 sites in PipelineEngine create PipelineResult. All currently pass `textMode: currentTextMode`. All change to `superStyle: currentSuperStyle`. Example:

```swift
// Before
PipelineResult(
    sessionId: sessionId,
    rawTranscript: rawTranscript,
    normalizedText: deterministicText,
    textMode: currentTextMode,
    ...
)

// After
PipelineResult(
    sessionId: sessionId,
    rawTranscript: rawTranscript,
    normalizedText: deterministicText,
    superStyle: currentSuperStyle,
    ...
)
```

### HistoryStore Consumer (D-03)

Current (HistoryStore.swift, line 25):
```swift
textMode: result.textMode.rawValue,
```

New:
```swift
textMode: result.superStyle?.rawValue ?? "none",
```

Note: HistoryItem.textMode remains a String field -- no SwiftData migration needed (project constraint).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| System prompt generation | Custom prompt builder | `SuperTextStyle.systemPrompt()` | Already exists from Phase 1, identical API to TextMode.systemPrompt() |
| LLM output contract | New contract logic | `SuperTextStyle.contract` returns `.normalization` | Already computed property, same result as TextMode.llmOutputContract |
| Style resolution | Manual bundleId mapping | `SuperStyleEngine.resolve(bundleId:mode:manualStyle:)` | Already exists from Phase 1, encapsulates all mapping logic |
| TextMode->SuperTextStyle bridge | Adapter/converter pattern | Direct replacement | D-01 explicitly forbids bridge pattern |

## Common Pitfalls

### Pitfall 1: Partial PipelineResult Migration
**What goes wrong:** Adding superStyle alongside textMode or leaving some PipelineResult construction sites with old field.
**Why it happens:** 9 PipelineResult construction sites across a 700-line file, easy to miss one.
**How to avoid:** D-03 is explicit -- complete replacement, no dual fields. Compiler error on every missed site because the `textMode:` parameter label will no longer exist in PipelineResult.init.
**Warning signs:** Build succeeds but some test creates PipelineResult with textMode parameter.

### Pitfall 2: NormalizationPipeline.postflight Signature
**What goes wrong:** Changing postflight to accept SuperTextStyle when it only needs the contract.
**Why it happens:** Temptation to mirror the old pattern of passing the whole type.
**How to avoid:** D-04 says gate signature does NOT change (that is Phase 4). The cleanest approach: change NormalizationPipeline.postflight to accept `contract: LLMOutputContract` instead of `textMode: TextMode`. This is minimal and forward-compatible.
**Warning signs:** NormalizationPipelineTests start importing SuperTextStyle when they only test gate behavior.

### Pitfall 3: AppState Analytics Metadata
**What goes wrong:** Breaking analytics by removing TextMode from analytics metadata.
**Why it happens:** AppState line 856 uses `context.textMode.rawValue` for analytics. But context.textMode comes from AppContextEngine, not PipelineEngine.
**How to avoid:** Only replace the pipeline data path (pipelineEngine.textMode -> pipelineEngine.superStyle). Leave AppContextEngine and its TextMode for Phase 9 (DELETE-03). Analytics metadata can stay as-is or switch to superStyle.rawValue.
**Warning signs:** Trying to modify AppContextEngine in this phase.

### Pitfall 4: Default Value for Optional SuperTextStyle
**What goes wrong:** nil superStyle in PipelineResult causes crashes or unexpected behavior in consumers.
**Why it happens:** TextMode had a non-optional default .universal. SuperTextStyle? is optional by design (standard mode has no style).
**How to avoid:** HistoryStore uses `result.superStyle?.rawValue ?? "none"` (D-03). Standard mode pipeline sets superStyle = nil. Super mode always has a resolved style from SuperStyleEngine.
**Warning signs:** Force-unwrapping superStyle anywhere, or using a non-optional default that masks the standard/super distinction.

### Pitfall 5: Missing Test Class Rename
**What goes wrong:** TextModeSnippetPromptTests in SnippetEngineTests.swift tests TextMode.systemPrompt, which still exists. But these tests should be updated to test SuperTextStyle.systemPrompt instead.
**Why it happens:** TEST-06 requires migrating these tests. The class name references TextMode.
**How to avoid:** Rename to SuperTextStyleSnippetPromptTests, change TextMode.universal.systemPrompt -> SuperTextStyle.normal.systemPrompt.
**Warning signs:** Tests pass but still exercise the old TextMode path that will be deleted in Phase 9.

### Pitfall 6: PipelineEngine stopRecording() Destructuring
**What goes wrong:** Variable name collision or missed update in the destructured tuple.
**Why it happens:** Line 322 destructures snapshotConfig: `let (currentProductMode, currentTextMode, currentHints, currentLLMClient) = snapshotConfig()`. This local variable `currentTextMode` is used ~15 times in the method.
**How to avoid:** Rename to `currentSuperStyle` in the destructuring. All usage sites within the method automatically update via find-replace.
**Warning signs:** Compiler errors on `currentTextMode` usage after snapshotConfig change.

## Code Examples

### PIPE-01: LLMClient Protocol Signature

```swift
// LLMClient.swift -- new protocol
protocol LLMClient: Sendable {
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String
}
```

### PIPE-01: PlaceholderLLMClient

```swift
// LLMClient.swift -- PlaceholderLLMClient
final class PlaceholderLLMClient: LLMClient, Sendable {
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        throw LLMError.networkError("LLM не настроен -- локальный worker ещё не реализован")
    }
}
```

### PIPE-02: LocalLLMClient.sendChatCompletion

```swift
// LocalLLMClient.swift -- signature and prompt generation
func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
    // ... same body, 'mode' -> 'superStyle' in sendChatCompletion call
}

private func sendChatCompletion(
    input: String,
    superStyle: SuperTextStyle,     // was: mode: TextMode
    hints: NormalizationHints,
    baseURL: URL,
    model: String
) async throws -> String {
    let systemPrompt = superStyle.systemPrompt(  // was: mode.systemPrompt(...)
        currentDate: hints.currentDate,
        personalDictionary: hints.personalDictionary,
        snippetContext: hints.snippetContext,
        appName: hints.appName
    )
    // ... rest identical
}
```

### PIPE-03: PipelineEngine Stored Property

```swift
// PipelineEngine.swift
private var _superStyle: SuperTextStyle? = nil

var superStyle: SuperTextStyle? {
    get { lock.lock(); defer { lock.unlock() }; return _superStyle }
    set { lock.lock(); defer { lock.unlock() }; _superStyle = newValue }
}
```

### PIPE-04: PipelineResult

```swift
// PipelineEngine.swift -- PipelineResult struct
struct PipelineResult {
    let sessionId: UUID
    let rawTranscript: String
    let normalizedText: String
    let superStyle: SuperTextStyle?    // was: textMode: TextMode
    // ... rest unchanged
}
```

### D-04: Gate Contract Bridge

```swift
// PipelineEngine.swift -- embedded snippet path (line ~477)
let gateResult = NormalizationGate.evaluate(
    input: deterministicText,
    output: llmOutput,
    contract: currentSuperStyle?.contract ?? .normalization,  // was: currentTextMode.llmOutputContract
    ignoredOutputLiterals: Set([SnippetPlaceholder.token])
)

// NormalizationPipeline.swift -- postflight signature
static func postflight(
    deterministicText: String,
    llmOutput: String,
    contract: LLMOutputContract,       // was: textMode: TextMode
    terminalPeriodEnabled: Bool = true,
    ignoredOutputLiterals: Set<String> = []
) -> NormalizationPipelinePostflight {
    // ... uses contract directly instead of textMode.llmOutputContract
}
```

### D-01: AppState Wiring

```swift
// AppState.swift -- handleActivated()
let superStyle = SuperStyleEngine.resolve(
    bundleId: context.bundleId,
    mode: .auto,
    manualStyle: .normal
)
pipelineEngine.superStyle = superStyle
```

### TEST-06: MockLLMClient

```swift
// TestHelpers.swift
final class MockLLMClient: LLMClient, @unchecked Sendable {
    var normalizeResult: String?
    var normalizeError: Error?
    private(set) var normalizeCalls: [(text: String, superStyle: SuperTextStyle, hints: NormalizationHints)] = []
    private let lock = NSLock()

    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        lock.lock()
        normalizeCalls.append((text, superStyle, hints))
        lock.unlock()

        if let error = normalizeError {
            throw error
        }
        return normalizeResult ?? text
    }
}
```

## Complete File Impact Inventory

### Production Files (8 files)

| File | Changes | Lines Affected |
|------|---------|----------------|
| `Govorun/Services/LLMClient.swift` | Protocol: mode->superStyle. PlaceholderLLMClient: same. | ~4 lines |
| `Govorun/Services/LocalLLMClient.swift` | normalize() + sendChatCompletion(): mode->superStyle, mode.systemPrompt->superStyle.systemPrompt | ~6 lines |
| `Govorun/Core/PipelineEngine.swift` | _textMode->_superStyle, computed prop, snapshotConfig tuple, 9 PipelineResult sites, 2 NormalizationGate.evaluate contract calls, 1 postflight call, local var rename | ~30 lines |
| `Govorun/Core/NormalizationPipeline.swift` | postflight(): textMode param->contract param, internal call | ~4 lines |
| `Govorun/App/AppState.swift` | handleActivated(): textMode wiring->SuperStyleEngine.resolve + superStyle wiring | ~5 lines |
| `Govorun/Storage/HistoryStore.swift` | save(): result.textMode.rawValue->result.superStyle?.rawValue ?? "none" | 1 line |
| `Govorun/Models/AnalyticsEvent.swift` | Possibly rename key or keep as-is (metadata key is a string, not a type reference) | 0-1 lines |
| `Govorun/Core/NormalizationGate.swift` | NO changes -- extension TextMode.llmOutputContract stays until Phase 9 deletion | 0 lines |

### Test Files (5 files)

| File | Changes |
|------|---------|
| `GovorunTests/TestHelpers.swift` | MockLLMClient: normalizeCalls tuple, normalize() signature |
| `GovorunTests/PipelineEngineTests.swift` | No direct textMode refs but makePipelineResult helper may need superStyle, and any assertions on result.textMode |
| `GovorunTests/AppContextEngineTests.swift` | TextModeSnippetPromptTests (but those reference TextMode directly -- update to SuperTextStyle) |
| `GovorunTests/HistoryStoreTests.swift` | makePipelineResult helper: textMode param, makeAppContext (AppContext.textMode stays for now) |
| `GovorunTests/SnippetEngineTests.swift` | TextModeSnippetPromptTests class: rename, use SuperTextStyle |
| `GovorunTests/NormalizationPipelineTests.swift` | 5 postflight calls with `textMode: .universal` -> `contract: .normalization` |

### NOT Changed in Phase 3

| File | Why |
|------|-----|
| `Govorun/Models/TextMode.swift` | Deleted in Phase 9 (DELETE-01) |
| `Govorun/Core/AppContextEngine.swift` | AppContext.textMode stays until Phase 9 (DELETE-03) |
| `Govorun/Views/AppModeSettingsView.swift` | Deleted in Phase 9 (DELETE-01) |
| `Govorun/Storage/SettingsStore.swift` | defaultTextMode stays until Phase 6/9 |
| `Govorun/Models/HistoryItem.swift` | textMode field is String, no migration needed |
| `Govorun/Core/NormalizationGate.swift` | Gate signature changes in Phase 4 (GATE-01) |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (986 tests across 38 files) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/PipelineEngineTests 2>&1 \| tail -5` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PIPE-01 | LLMClient.normalize uses superStyle param | unit | MockLLMClient conformance compiles; PipelineEngineTests exercise normalize | Exists (update) |
| PIPE-02 | LocalLLMClient uses SuperTextStyle.systemPrompt() | unit | LocalLLMClient compiles with new signature | Exists (update) |
| PIPE-03 | PipelineEngine stores _superStyle | unit | PipelineEngineTests set engine.superStyle | Exists (update) |
| PIPE-04 | PipelineResult.superStyle replaces textMode | unit | All PipelineEngineTests check result.superStyle | Exists (update) |
| TEST-06 | MockLLMClient, AppContextEngineTests, HistoryStoreTests, SnippetEngineTests migrated | unit | Full test suite passes | Exists (update) |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. Tests need updating, not creating.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis of all 8 production files and 5 test files
- `Govorun/Services/LLMClient.swift` -- protocol signature, PlaceholderLLMClient
- `Govorun/Services/LocalLLMClient.swift` -- sendChatCompletion with mode.systemPrompt()
- `Govorun/Core/PipelineEngine.swift` -- 21 textMode refs, snapshotConfig(), 9 PipelineResult sites
- `Govorun/Core/NormalizationPipeline.swift` -- postflight with textMode param
- `Govorun/Core/NormalizationGate.swift` -- TextMode.llmOutputContract extension
- `Govorun/Models/SuperTextStyle.swift` -- systemPrompt(), contract, styleBlock, applyDeterministic
- `Govorun/Core/SuperStyleEngine.swift` -- resolve(bundleId:mode:manualStyle:)
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` -- design spec (referenced but not read; CONTEXT.md captures decisions)

### Secondary (MEDIUM confidence)
- Phase 1 and Phase 2 completion status from STATE.md and REQUIREMENTS.md traceability table

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- pure Swift refactoring, no external dependencies
- Architecture: HIGH -- all code read, all call sites identified, compiler enforces correctness
- Pitfalls: HIGH -- complete file inventory, all edge cases from codebase review

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable -- internal refactoring, no external API changes)
