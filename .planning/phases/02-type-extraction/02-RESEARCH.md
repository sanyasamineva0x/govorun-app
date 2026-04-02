# Phase 2: Type Extraction - Research

**Researched:** 2026-03-30
**Domain:** Swift refactoring -- extracting types from a monolithic file into separate files, removing a field from a struct
**Confidence:** HIGH

## Summary

Phase 2 is a mechanical refactoring: extract three types (`SnippetPlaceholder`, `SnippetContext`, `NormalizationHints`) from `Govorun/Models/TextMode.swift` into individual files under `Models/`, and remove the `textMode: TextMode` field from `NormalizationHints`. After this phase, `TextMode.swift` contains only the `enum TextMode` and its extensions (ready for deletion in Phase 9).

The codebase already follows a one-type-per-file pattern in `Models/` (`ProductMode.swift`, `RecordingMode.swift`, `SuperTextStyle.swift`, etc.), so new files follow established conventions. XcodeGen uses directory-based source discovery (`path: Govorun`), so no `project.yml` changes are needed -- new `.swift` files in `Models/` are automatically included.

The critical change is removing `textMode` from `NormalizationHints`. This field is currently passed through to `NormalizationHints` in two call sites (AppState and PipelineEngine) and forwarded when creating `hintsWithSnippet`. Removing it requires updating 7 files (production + test). The `LLMClient.normalize()` still takes `mode: TextMode` as a separate parameter (Phase 3 will change that to `superStyle:`), so the pipeline continues to work -- `textMode` in hints was redundant with the `mode:` parameter.

**Primary recommendation:** Extract types one-by-one (SnippetPlaceholder, SnippetContext, NormalizationHints), then remove `textMode` field and fix all callers. Compile-test after each extraction to catch issues immediately.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Удалить поле `textMode: TextMode` из NormalizationHints. Не заменять на superStyle -- это задача Фазы 3 (Pipeline Integration). После удаления struct содержит: personalDictionary, appName, currentDate, snippetContext.
- **D-02:** Обновить ВСЕ потребители NormalizationHints (7 файлов): убрать передачу textMode: параметра. Включая тесты -- они тоже обновляются для компиляции.
- **D-03:** Каждый тип в отдельном файле (как в REQUIREMENTS): `Models/SnippetPlaceholder.swift`, `Models/SnippetContext.swift`, `Models/NormalizationHints.swift`. Не объединять.

### Claude's Discretion
- Порядок MARK-секций в новых файлах
- Нужно ли добавлять Sendable conformance при извлечении (если компилятор ругается)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXTRACT-01 | SnippetPlaceholder вынесен в Govorun/Models/SnippetPlaceholder.swift | Caseless enum, 2 lines. Move as-is with `import Foundation`. No consumers change -- all reference `SnippetPlaceholder.token` which resolves to same type. |
| EXTRACT-02 | SnippetContext вынесен в Govorun/Models/SnippetContext.swift | Struct Equatable, 3 lines. Move as-is. Used by SuperTextStyle.systemPrompt(), PipelineEngine, NormalizationGateTests, SnippetEngineTests -- all via type name, no import changes needed. |
| EXTRACT-03 | NormalizationHints вынесен в Govorun/Models/NormalizationHints.swift (без поля textMode) | Struct Equatable, 21 lines. Remove `textMode: TextMode` field and its init parameter. Update 7 consumer files. |
</phase_requirements>

## Architecture Patterns

### Current File Structure (Models/)
```
Govorun/Models/
  ActivationKey.swift       # enum + extensions
  AnalyticsEvent.swift      # struct
  DictionaryEntry.swift     # struct
  HistoryItem.swift         # @Model class
  ProductMode.swift         # enum
  RecordingMode.swift       # enum
  Snippet.swift             # @Model class
  SuperModelCatalog.swift   # struct
  SuperModelDownloadSpec.swift
  SuperModelDownloadState.swift
  SuperTextStyle.swift      # enum (Phase 1)
  TextMode.swift            # enum + SnippetPlaceholder + SnippetContext + NormalizationHints
```

### After Extraction
```
Govorun/Models/
  ...existing files...
  SnippetPlaceholder.swift  # NEW: caseless enum
  SnippetContext.swift       # NEW: struct Equatable
  NormalizationHints.swift   # NEW: struct Equatable (without textMode)
  TextMode.swift             # REDUCED: only enum TextMode + extensions
```

### Pattern: Models/ File Convention
All `Models/` files follow the same pattern:
1. `import Foundation` (only Foundation, never AppKit/SwiftUI)
2. One `// MARK: -` section header in Russian
3. Single public type (enum, struct, or @Model class)
4. Minimal or no computed properties for pure data types

**Example from ProductMode.swift (established pattern):**
```swift
import Foundation

// MARK: - Продуктовый режим

enum ProductMode: String, CaseIterable, Codable {
    case standard
    case superMode = "super"
    // ...computed properties...
}
```

### Anti-Patterns to Avoid
- **Adding unnecessary imports:** SnippetPlaceholder and SnippetContext need only `import Foundation`. NormalizationHints also only `import Foundation`.
- **Changing visibility modifiers:** All three types are currently `internal` (default). Keep them internal -- no `public` or `open`.
- **Breaking the init signature unexpectedly:** NormalizationHints has default parameter values. When removing `textMode`, ensure remaining defaults stay unchanged (`personalDictionary: [:]`, `appName: nil`, `currentDate: Date()`, `snippetContext: nil`).

## Exact Types to Extract

### SnippetPlaceholder (TextMode.swift lines 192-194)
```swift
// Current:
enum SnippetPlaceholder {
    static let token = "[[[GOVORUN_SNIPPET]]]"
}
```
Caseless enum used as a namespace for a single static constant. No changes needed beyond moving.

**Consumers (no code changes needed):**
- `Govorun/Models/SuperTextStyle.swift` -- `SnippetPlaceholder.token` in systemPrompt()
- `Govorun/Models/TextMode.swift` -- `SnippetPlaceholder.token` in systemPrompt() (stays in TextMode.swift)
- `GovorunTests/NormalizationGateTests.swift` -- `SnippetPlaceholder.token` as ignoredOutputLiterals

### SnippetContext (TextMode.swift lines 198-200)
```swift
// Current:
struct SnippetContext: Equatable {
    let trigger: String
}
```
Simple value type. No changes needed beyond moving.

**Consumers (no code changes needed):**
- `Govorun/Models/SuperTextStyle.swift` -- `snippetContext: SnippetContext?` parameter
- `Govorun/Models/TextMode.swift` -- `snippetContext: SnippetContext?` parameter (stays)
- `Govorun/Core/PipelineEngine.swift` -- creates `SnippetContext(trigger:)`
- `GovorunTests/SnippetEngineTests.swift` -- creates `SnippetContext(trigger:)`

### NormalizationHints (TextMode.swift lines 204-224)
```swift
// Current (21 lines):
struct NormalizationHints: Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let textMode: TextMode        // <-- REMOVE THIS
    let currentDate: Date
    let snippetContext: SnippetContext?

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        textMode: TextMode = .universal,  // <-- REMOVE THIS
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil
    ) { ... }
}
```

**After extraction (without textMode):**
```swift
import Foundation

// MARK: - Хинты для нормализации

struct NormalizationHints: Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let currentDate: Date
    let snippetContext: SnippetContext?

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil
    ) {
        self.personalDictionary = personalDictionary
        self.appName = appName
        self.currentDate = currentDate
        self.snippetContext = snippetContext
    }
}
```

## Consumer Updates (D-02: All 7 Files)

Complete list of changes needed when removing `textMode` from NormalizationHints:

### 1. AppState.swift (line ~847-851)
```swift
// BEFORE:
pipelineEngine.hints = NormalizationHints(
    personalDictionary: dictionary.llmReplacements,
    appName: context.appName,
    textMode: context.textMode  // <-- REMOVE
)

// AFTER:
pipelineEngine.hints = NormalizationHints(
    personalDictionary: dictionary.llmReplacements,
    appName: context.appName
)
```

### 2. PipelineEngine.swift (line ~449-455)
```swift
// BEFORE:
let hintsWithSnippet = NormalizationHints(
    personalDictionary: currentHints.personalDictionary,
    appName: currentHints.appName,
    textMode: currentHints.textMode,    // <-- REMOVE
    currentDate: currentHints.currentDate,
    snippetContext: snippetCtx
)

// AFTER:
let hintsWithSnippet = NormalizationHints(
    personalDictionary: currentHints.personalDictionary,
    appName: currentHints.appName,
    currentDate: currentHints.currentDate,
    snippetContext: snippetCtx
)
```

### 3. LLMClient.swift -- no change to `NormalizationHints` usage
The protocol signature `normalize(_ text: String, mode: TextMode, hints: NormalizationHints)` does NOT change in Phase 2. The `mode:` parameter is separate from hints. Phase 3 changes this.

### 4. LocalLLMClient.swift (line ~50, ~136)
The `normalize()` signature and `sendChatCompletion()` do NOT read `hints.textMode` directly -- they use the `mode: TextMode` parameter. No changes needed for the textMode removal from hints. The method already receives `mode` separately.

### 5. GovorunTests/LocalLLMClientTests.swift
All test calls use `NormalizationHints(currentDate: makeDate())` -- they never pass `textMode:` explicitly (it was using the default `.universal`). After removing `textMode` from the struct, these calls compile without changes because `textMode:` was using the default value.

### 6. GovorunTests/PipelineEngineTests.swift (lines ~766-770, ~788-792, ~915-919, ~937-941)
Four places create NormalizationHints with explicit `textMode: .chat`. These must be updated:
```swift
// BEFORE:
engine.hints = NormalizationHints(
    personalDictionary: ["жира": "Jira"],
    appName: "Telegram",
    textMode: .chat          // <-- REMOVE
)

// AFTER:
engine.hints = NormalizationHints(
    personalDictionary: ["жира": "Jira"],
    appName: "Telegram"
)
```

### 7. GovorunTests/TestHelpers.swift (line ~32-35)
MockLLMClient stores `normalizeCalls: [(text: String, mode: TextMode, hints: NormalizationHints)]` -- this is unchanged since it captures the `mode:` parameter and `hints` separately. The mock's `normalize()` signature also stays unchanged. No textMode-in-hints change needed.

**Revised actual consumer update count:**
- Files requiring code changes for textMode removal: **3** (AppState.swift, PipelineEngine.swift, PipelineEngineTests.swift)
- Files requiring NO changes for textMode removal: **4** (LLMClient.swift, LocalLLMClient.swift, LocalLLMClientTests.swift, TestHelpers.swift)
- Total files affected by file extraction (compile): **0** (Swift resolves types project-wide, no import changes)

## Sendable Conformance (Claude's Discretion)

The project uses `SWIFT_STRICT_CONCURRENCY: complete`. Check whether the extracted types need explicit `Sendable` conformance:

- **SnippetPlaceholder**: Caseless enum with only `static let`. Enums without associated values are implicitly `Sendable`. No change needed.
- **SnippetContext**: Struct with a single `let trigger: String`. Structs with only `Sendable` stored properties are implicitly `Sendable`. No change needed.
- **NormalizationHints**: Struct with `let` properties of types `[String: String]`, `String?`, `Date`, `SnippetContext?`. All are `Sendable`. The struct is implicitly `Sendable`. No change needed.

**Recommendation:** Do NOT add explicit `: Sendable` conformance. The types are already implicitly Sendable. The existing codebase does not add explicit Sendable to value types (verified: ProductMode, RecordingMode do not declare Sendable). Only add if the compiler produces an error after extraction (unlikely but possible if a future Swift version changes inference rules).

## Common Pitfalls

### Pitfall 1: Forgetting to Remove the textMode Default from NormalizationHints init
**What goes wrong:** If `textMode` parameter is removed from the stored property but left in `init`, or vice versa, the compiler will error.
**How to avoid:** Remove both the stored property AND the init parameter AND the `self.textMode = textMode` assignment together.

### Pitfall 2: Missing a NormalizationHints Call Site
**What goes wrong:** A call site passes `textMode:` to NormalizationHints init, compiler error.
**How to avoid:** After removing `textMode`, build immediately. The compiler will flag every stale call site. The grep audit above found all 6 explicit `textMode:` usages in NormalizationHints constructors: 1 in AppState, 1 in PipelineEngine, 4 in PipelineEngineTests.

### Pitfall 3: XcodeGen Not Regenerated
**What goes wrong:** New files exist on disk but Xcode project doesn't see them.
**Why it happens:** `project.yml` uses directory-based sources (`path: Govorun`), so `xcodegen generate` must be run after adding new files. However, this only matters for Xcode IDE -- `xcodebuild` via CLI with `xcodegen generate` in the build script should be fine.
**How to avoid:** Run `xcodegen generate` after adding new files, before building.

### Pitfall 4: Leaving Dead Code in TextMode.swift
**What goes wrong:** Types are copied to new files but not removed from TextMode.swift, causing "duplicate declaration" errors.
**How to avoid:** After creating each new file, immediately remove the corresponding block from TextMode.swift and verify compilation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding all usages of a type | Manual file search | Compiler errors after removal | Swift compiler is the authoritative source of all references |
| Project file updates | Manual project.yml editing | `xcodegen generate` | Directory-based sources auto-discover new .swift files |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, Swift 5.10) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 \| tail -5` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXTRACT-01 | SnippetPlaceholder in own file, project compiles | compilation | `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` | N/A (compilation check) |
| EXTRACT-02 | SnippetContext in own file, project compiles | compilation | same as above | N/A (compilation check) |
| EXTRACT-03 | NormalizationHints in own file without textMode, all 986+ tests pass | unit (existing) | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` | Existing tests cover this |

### Sampling Rate
- **Per task commit:** `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` (compilation check)
- **Per wave merge:** Full test suite (986+ tests)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. No new tests needed for this phase. The success criterion is that ALL existing 986+ tests pass without modification (beyond removing `textMode:` from test constructors).

## Project Constraints (from CLAUDE.md)

- **No Co-Authored-By** in commits -- public repo, no AI attribution
- Commits in Russian: `feat: добавить X`, `fix: исправить Y`
- Comments minimal, in Russian
- Models/ -- pure value types, `import Foundation` only
- One type = one file (established pattern)
- `SWIFT_STRICT_CONCURRENCY: complete` -- compiler enforces Sendable
- No force unwrap (!) in production code
- TDD: but this phase needs no new tests, only compilation verification
- Must run `xcodegen generate` after adding new source files
- Build command: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection of `Govorun/Models/TextMode.swift` (lines 192-224) -- exact types to extract
- Direct codebase inspection of all 7 consumer files listed in CONTEXT.md -- verified exact change locations
- `project.yml` -- confirmed directory-based source discovery (no manual file registration)
- Existing `Models/` files (ProductMode.swift, Snippet.swift) -- verified established patterns

### Secondary (MEDIUM confidence)
- None needed -- this is a pure codebase refactoring with no external dependencies

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, pure Swift refactoring
- Architecture: HIGH -- follows exactly established Models/ patterns visible in codebase
- Pitfalls: HIGH -- all verified by direct code inspection and grep audit

**Research date:** 2026-03-30
**Valid until:** indefinite (codebase-specific, no external dependency drift)
