# Phase 1: Foundation Types - Research

**Researched:** 2026-03-29
**Domain:** Swift enums, static utility types, XCTest unit testing
**Confidence:** HIGH

## Summary

Phase 1 creates the foundational type system for text styles v2: `SuperTextStyle` enum (relaxed/normal/formal), `SuperStyleMode` enum (auto/manual), and `SuperStyleEngine` (caseless enum with static resolve method). All three are pure Swift value types in Models/ and Core/ -- no UI, no services, no external dependencies. The existing codebase provides clear patterns to follow: `ProductMode` for enum layout, `NormalizationGate` for caseless enum with static methods, `TextMode` for prompt generation.

The spec design document (`docs/superpowers/specs/2026-03-29-text-styles-v2-design.md`) is the single source of truth for brand/tech alias tables, bundleId mappings, and prompt structure. `LLMOutputContract` already exists in `Core/NormalizationGate.swift` (lines 5-8) and requires no changes -- SuperTextStyle.contract simply returns .normalization for all three styles.

**Primary recommendation:** Follow existing `ProductMode` pattern exactly for `SuperTextStyle` enum structure. Follow existing `NormalizationGate` pattern for `SuperStyleEngine` caseless enum. Keep alias tables as `static let` on `SuperTextStyle`. Tests should follow the existing XCTestCase style in the GovorunTests target.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Pure static -- caseless enum `SuperStyleEngine` with `static func resolve(bundleId:mode:manualStyle:) -> SuperTextStyle`. No state, caller passes all parameters.
- **D-02:** File: `Govorun/Core/SuperStyleEngine.swift`. Pattern like NormalizationGate -- caseless enum + static methods.
- **D-03:** SuperStyleMode -- separate enum `enum SuperStyleMode: String, CaseIterable { case auto, manual }`. Two independent axes: mode (auto/manual) + style (relaxed/normal/formal).
- **D-04:** LLMOutputContract stays in `Core/NormalizationGate.swift` where it already lives. Single target, no module boundaries -- SuperTextStyle in Models/ freely references Core/.
- **D-05:** Brand (24) + tech term (4) alias tables defined as `static let` on SuperTextStyle in `Models/SuperTextStyle.swift`. Format: `[(original: String, relaxed: String)]`.
- **D-06:** Slang expansions (formal) -- only via LLM, no fixed table. Gate treats slang replacements as valid in formal (lenient for slang).
- **D-07:** systemPrompt() = basePrompt + styleBlock. basePrompt contains normalization contract (no rephrasing, surgical replacements). styleBlock depends on style.
- **D-08:** styleBlock for relaxed includes full brand + tech term table inline (all 24+4 pairs). More tokens but more accurate replacements.
- **D-09:** styleBlock for normal -- minimal (standard checks, brands/tech terms -> original).
- **D-10:** styleBlock for formal -- original for brands/tech terms + "expand slang to full forms".

### Claude's Discretion
- Exact wording of basePrompt and styleBlock strings
- Test structure (XCTestCase layout, test naming)
- Order of properties on SuperTextStyle enum
- displayName for UI (localized style names)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STYLE-01 | SuperTextStyle enum (relaxed/normal/formal) with rawValue: String, CaseIterable | ProductMode pattern provides exact template; raw values from spec |
| STYLE-02 | Each style has computed properties: styleBlock, systemPrompt, contract, applyDeterministic | TextMode.swift provides systemPrompt/styleBlock template; contract references existing LLMOutputContract |
| STYLE-03 | LLMOutputContract enum (.normalization, .rewriting) -- .rewriting as stub for 2.5 | Already exists in NormalizationGate.swift lines 5-8, no changes needed |
| STYLE-04 | SuperTextStyle.contract returns .normalization for all three styles (v2) | Mirrors TextMode.llmOutputContract pattern in NormalizationGate.swift lines 10-17 |
| STYLE-05 | applyDeterministic controls initial capitalization (relaxed -> lowercase, normal/formal -> uppercase) | DeterministicNormalizer.normalize() line 129 shows capitalization pattern; new method operates on final text |
| ENGINE-01 | SuperStyleEngine resolves style by bundleId in auto mode (hard mapping from spec) | Spec provides 9 bundleIds in 3 groups; AppContextEngine shows existing mapping pattern |
| ENGINE-02 | SuperStyleEngine returns chosen style in manual mode | D-01: resolve(bundleId:mode:manualStyle:) -- when mode == .manual, return manualStyle directly |
| ENGINE-03 | Unknown bundleIds -> normal in auto mode | Spec: "everything else -> normal"; default case in switch |
| ENGINE-04 | Auto mode: relaxed for messengers (Telegram, WhatsApp, Viber, VK, Messages, Discord) | 6 bundleIds from spec design doc |
| ENGINE-05 | Auto mode: formal for mail clients (Mail, Spark, Outlook) | 3 bundleIds from spec design doc |
| TEST-01 | Unit tests SuperTextStyle: enum, styleBlock, systemPrompt, applyDeterministic | XCTest infrastructure exists (986 tests, GovorunTests target); new file SuperTextStyleTests.swift |
| TEST-02 | Unit tests SuperStyleEngine: bundleId mapping, auto/manual | New file SuperStyleEngineTests.swift; test each bundleId + edge cases |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Language**: Swift 5.10+, macOS 14.0+ (Sonoma), Apple Silicon (M1+)
- **Layer rules**: Core/ does NOT import SwiftUI or AppKit (Foundation only); Models/ are pure value types
- **No Co-Authored-By**: public repo, no signs of AI authorship
- **Commits in Russian**: `feat: добавить X`, `fix: исправить Y`
- **TDD**: test (red) -> code (green) -> refactor
- **Protocols for DI**: all services via protocols, mocks in tests
- **No force unwrap (!)** in production code
- **async/await**, not completion handlers
- **@MainActor only for UI code**
- **Comments minimal, in Russian**
- **Strict concurrency**: `SWIFT_STRICT_CONCURRENCY: complete`
- **Import only what's needed** per file
- **Git process**: `feat/<name>` or `fix/<name>` -> PR -> squash merge -> delete branch; one live branch at a time

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.3 (Xcode 26.4) | Language runtime | Installed on machine; project targets Swift 5.10+ compatibility |
| XCTest | System | Unit testing framework | Already used for 986 tests in GovorunTests target |
| Foundation | System | String manipulation, dates | Only framework allowed in Core/ and Models/ |

### Supporting
No additional libraries needed. Phase 1 is pure Swift types with no external dependencies.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| XCTest | swift-testing | Project already uses XCTest with 986 tests; mixing frameworks adds complexity |
| Hardcoded alias tables | plist/JSON resource | D-05 locks static let on enum -- no runtime loading needed for 28 entries |

## Architecture Patterns

### File Placement
```
Govorun/
  Models/
    SuperTextStyle.swift      # NEW: enum + computed properties + alias tables
    ProductMode.swift          # EXISTING: pattern reference
    TextMode.swift             # EXISTING: prompt template reference (will be deleted Phase 9)
  Core/
    SuperStyleEngine.swift     # NEW: caseless enum + static resolve()
    NormalizationGate.swift    # EXISTING: LLMOutputContract lives here (untouched)
GovorunTests/
    SuperTextStyleTests.swift  # NEW: tests for enum + properties
    SuperStyleEngineTests.swift # NEW: tests for resolve()
```

### Pattern 1: Enum with String RawValue (from ProductMode.swift)
**What:** Enum conforming to String, CaseIterable, Codable with computed properties
**When to use:** SuperTextStyle definition
**Example:**
```swift
// Source: Govorun/Models/ProductMode.swift (existing pattern)
enum SuperTextStyle: String, CaseIterable, Codable {
    case relaxed
    case normal
    case formal
}
```

### Pattern 2: Caseless Enum as Namespace (from NormalizationGate.swift)
**What:** Enum with no cases, only static methods -- prevents instantiation
**When to use:** SuperStyleEngine utility namespace
**Example:**
```swift
// Source: Govorun/Core/NormalizationGate.swift (existing pattern)
enum SuperStyleEngine {
    static func resolve(
        bundleId: String,
        mode: SuperStyleMode,
        manualStyle: SuperTextStyle
    ) -> SuperTextStyle {
        switch mode {
        case .auto:
            return autoResolve(bundleId: bundleId)
        case .manual:
            return manualStyle
        }
    }
}
```

### Pattern 3: Prompt Generation (from TextMode.swift)
**What:** basePrompt as static method, styleBlock as computed property, systemPrompt() combining both
**When to use:** SuperTextStyle prompt generation
**Example:**
```swift
// Source: Govorun/Models/TextMode.swift lines 17-188 (template)
extension SuperTextStyle {
    static func basePrompt(currentDate: Date, personalDictionary: [String: String] = [:]) -> String {
        // ... normalization contract prompt
    }

    var styleBlock: String {
        switch self {
        case .relaxed: // ... brand aliases inline
        case .normal:  // ... minimal
        case .formal:  // ... slang expansion instruction
        }
    }

    func systemPrompt(
        currentDate: Date,
        personalDictionary: [String: String] = [:],
        snippetContext: SnippetContext? = nil,
        appName: String? = nil
    ) -> String {
        var prompt = Self.basePrompt(currentDate: currentDate, personalDictionary: personalDictionary)
        prompt += "\n\n" + styleBlock
        // ... app context, snippet context
        return prompt
    }
}
```

### Pattern 4: Alias Table Structure (decision D-05)
**What:** Static let arrays of tuples for brand/tech term mappings
**When to use:** SuperTextStyle alias data
**Example:**
```swift
extension SuperTextStyle {
    static let brandAliases: [(original: String, relaxed: String)] = [
        ("Slack", "слак"),
        ("Zoom", "зум"),
        // ... 22 more from spec
    ]

    static let techTermAliases: [(original: String, relaxed: String)] = [
        ("PDF", "пдф"),
        ("API", "апи"),
        ("URL", "урл"),
        ("PR", "пр"),
    ]
}
```

### Anti-Patterns to Avoid
- **Importing AppKit or SwiftUI in Models/ or Core/**: Layer rules prohibit this. Foundation only.
- **Storing state in SuperStyleEngine**: D-01 mandates pure static, no stored properties. Caller passes everything.
- **Moving LLMOutputContract**: D-04 explicitly forbids moving it from NormalizationGate.swift.
- **Creating a fixed slang expansion table**: D-06 says slang expansions are LLM-only, no hardcoded table.
- **Adding SuperTextStyle as a parameter to NormalizationGate.evaluate()**: That is Phase 4 (GATE-01..04). Phase 1 only creates the types -- no integration changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Prompt text | Custom string builder | Multiline string literals with `\()` interpolation | TextMode.swift already uses this; Swift multiline strings handle indentation cleanly |
| BundleId lookup | Dictionary with fallback logic | Switch statement with default case | 9 total bundleIds -- switch is clearer and matches spec structure exactly |
| Capitalization transforms | Manual Character-level manipulation | `String.prefix(1).lowercased()` / `.uppercased()` + `dropFirst()` | Foundation String APIs handle Unicode correctly |

**Key insight:** This phase is intentionally simple -- pure types with no external dependencies. The complexity lives in downstream phases (Gate, Pipeline). Do not prematurely integrate.

## Common Pitfalls

### Pitfall 1: Coupling SuperTextStyle to TextMode
**What goes wrong:** Referencing TextMode from SuperTextStyle or vice versa, creating circular dependency
**Why it happens:** TextMode has systemPrompt/styleBlock that look similar -- tempting to inherit
**How to avoid:** SuperTextStyle is completely independent. Copy the basePrompt logic, adapt styleBlock independently. TextMode is deleted in Phase 9.
**Warning signs:** Import of TextMode in SuperTextStyle.swift

### Pitfall 2: Modifying NormalizationGate.evaluate() Signature
**What goes wrong:** Adding `superStyle` parameter to evaluate() in Phase 1
**Why it happens:** Seeing that Gate needs style-awareness (GATE-01) and trying to do it early
**How to avoid:** Phase 1 only creates types. Gate integration is Phase 4. SuperTextStyle.contract exists but is not wired into Gate yet.
**Warning signs:** Changes to NormalizationGate.swift beyond what LLMOutputContract already is

### Pitfall 3: SuperStyleMode Placement
**What goes wrong:** Putting SuperStyleMode inside SuperTextStyle or SuperStyleEngine
**Why it happens:** Feels like it "belongs" with one of them
**How to avoid:** D-03 says separate enum. Two independent axes: mode (auto/manual) and style (relaxed/normal/formal). SuperStyleMode can live in the same file as SuperTextStyle (Models/) or SuperStyleEngine (Core/) -- Claude's discretion. Recommended: in SuperTextStyle.swift since it is a Models/ type.
**Warning signs:** Nested enum definition inside another type

### Pitfall 4: basePrompt Diverging from TextMode.basePrompt
**What goes wrong:** Writing a new basePrompt from scratch that misses edge cases (self-correction, filler removal, canonical forms)
**Why it happens:** The basePrompt is long and complex; easy to summarize rather than port
**How to avoid:** Port the basePrompt text from TextMode.basePrompt() verbatim. The normalization contract in basePrompt does NOT change between TextMode and SuperTextStyle -- only styleBlock changes.
**Warning signs:** basePrompt shorter than ~80 lines or missing sections like SAMOCORRECTION, TRANSLITERATION, NUMBERS

### Pitfall 5: Missing Codable Conformance
**What goes wrong:** Forgetting Codable on SuperTextStyle; HistoryStore saves rawValue to SwiftData
**Why it happens:** Phase 1 focuses on computed properties, forgets persistence needs
**How to avoid:** Follow ProductMode pattern exactly: `enum SuperTextStyle: String, CaseIterable, Codable`
**Warning signs:** Enum definition missing Codable

### Pitfall 6: applyDeterministic Scope Creep
**What goes wrong:** Implementing full deterministic normalization (fillers, brands, numbers) inside applyDeterministic
**Why it happens:** DeterministicNormalizer has extensive logic; seems like applyDeterministic should replicate it
**How to avoid:** Per spec and STYLE-05, applyDeterministic controls ONLY initial capitalization (relaxed -> lowercase, normal/formal -> uppercase). Terminal period is handled by postflight (Phase 5). Brand/tech replacements are LLM + DeterministicNormalizer (not applyDeterministic).
**Warning signs:** applyDeterministic doing more than capitalization transform

## Code Examples

### SuperTextStyle Enum (verified pattern from ProductMode.swift + spec)
```swift
// File: Govorun/Models/SuperTextStyle.swift
import Foundation

enum SuperTextStyle: String, CaseIterable, Codable {
    case relaxed
    case normal
    case formal
}

// MARK: - Режим выбора стиля

enum SuperStyleMode: String, CaseIterable {
    case auto
    case manual
}
```

### Computed Properties (verified pattern from TextMode.swift)
```swift
extension SuperTextStyle {
    var contract: LLMOutputContract {
        // v2: все три -> .normalization. v2.5: formal -> .rewriting
        .normalization
    }

    var displayName: String {
        switch self {
        case .relaxed: "Расслабленный"
        case .normal: "Обычный"
        case .formal: "Формальный"
        }
    }
}
```

### applyDeterministic (per STYLE-05)
```swift
extension SuperTextStyle {
    func applyDeterministic(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        switch self {
        case .relaxed:
            return text.prefix(1).lowercased() + text.dropFirst()
        case .normal, .formal:
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }
}
```

### SuperStyleEngine (verified pattern from NormalizationGate caseless enum)
```swift
// File: Govorun/Core/SuperStyleEngine.swift
import Foundation

enum SuperStyleEngine {
    private static let messengerBundleIds: Set<String> = [
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "com.viber.osx",
        "com.vk.messenger",
        "com.apple.MobileSMS",
        "com.hnc.Discord",
    ]

    private static let mailBundleIds: Set<String> = [
        "com.apple.mail",
        "com.readdle.smartemail-macos",
        "com.microsoft.Outlook",
    ]

    static func resolve(
        bundleId: String,
        mode: SuperStyleMode,
        manualStyle: SuperTextStyle
    ) -> SuperTextStyle {
        switch mode {
        case .manual:
            return manualStyle
        case .auto:
            if messengerBundleIds.contains(bundleId) { return .relaxed }
            if mailBundleIds.contains(bundleId) { return .formal }
            return .normal
        }
    }
}
```

### Test Pattern (verified from NormalizationGateTests.swift)
```swift
// File: GovorunTests/SuperStyleEngineTests.swift
@testable import Govorun
import XCTest

final class SuperStyleEngineTests: XCTestCase {
    func test_auto_mode_returns_relaxed_for_telegram() {
        let style = SuperStyleEngine.resolve(
            bundleId: "ru.keepcoder.Telegram",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_manual_mode_returns_selected_style_regardless_of_bundleId() {
        let style = SuperStyleEngine.resolve(
            bundleId: "ru.keepcoder.Telegram",
            mode: .manual,
            manualStyle: .formal
        )
        XCTAssertEqual(style, .formal)
    }
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (system, Xcode 26.4) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests && xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperStyleEngineTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STYLE-01 | SuperTextStyle enum compiles, has 3 cases, rawValues, CaseIterable | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | Wave 0 |
| STYLE-02 | Each style has styleBlock, systemPrompt, contract, applyDeterministic | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | Wave 0 |
| STYLE-03 | LLMOutputContract has .normalization and .rewriting | unit | already covered by NormalizationGateTests | existing |
| STYLE-04 | contract returns .normalization for all 3 styles | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | Wave 0 |
| STYLE-05 | applyDeterministic: relaxed->lowercase, normal/formal->uppercase | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | Wave 0 |
| ENGINE-01 | resolve returns correct style for known bundleIds in auto | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |
| ENGINE-02 | resolve returns manualStyle when mode is .manual | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |
| ENGINE-03 | unknown bundleId -> .normal in auto mode | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |
| ENGINE-04 | relaxed for 6 messenger bundleIds | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |
| ENGINE-05 | formal for 3 mail bundleIds | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |
| TEST-01 | Tests for SuperTextStyle exist and pass | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | Wave 0 |
| TEST-02 | Tests for SuperStyleEngine exist and pass | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests -only-testing:GovorunTests/SuperStyleEngineTests`
- **Per wave merge:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `GovorunTests/SuperTextStyleTests.swift` -- covers STYLE-01, STYLE-02, STYLE-04, STYLE-05, TEST-01
- [ ] `GovorunTests/SuperStyleEngineTests.swift` -- covers ENGINE-01..05, TEST-02

Note: No framework install needed. XCTest is system-provided. No conftest/shared fixtures needed -- tests are self-contained.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| TextMode (6 cases: chat/email/document/note/code/universal) | SuperTextStyle (3 cases: relaxed/normal/formal) | v2 (this project) | Simpler model, style-aware rather than app-mode-aware |
| Per-app overrides via AppModeOverriding | Global auto/manual switch | v2 (this project) | Removed complexity of per-app settings UI |
| TextMode.llmOutputContract (on TextMode) | SuperTextStyle.contract (on SuperTextStyle) | v2 (this project) | Contract lives on the new enum |

**Deprecated/outdated:**
- TextMode enum: will be deleted in Phase 9. Phase 1 types exist alongside it -- no conflict.
- AppModeOverriding: deleted in Phase 9. Not touched in Phase 1.

## Open Questions

1. **basePrompt -- port or adapt?**
   - What we know: TextMode.basePrompt() (lines 18-121 of TextMode.swift) is the current production prompt. The normalization contract in basePrompt is style-independent.
   - What's unclear: Whether the examples section in basePrompt (lines 93-119) should change for SuperTextStyle. Current examples show `"открой жиру" -> "Открой Jira"` which is normal/formal behavior but not relaxed.
   - Recommendation: Port basePrompt verbatim for now. Style-specific examples go in styleBlock. The basePrompt examples show the normalization contract (what LLM should/shouldn't do), not style. Relaxed styleBlock will override the brand handling with its own inline table.

2. **SuperStyleMode file placement**
   - What we know: D-03 says separate enum. It is a mode selector, not a style.
   - What's unclear: Models/SuperTextStyle.swift or Core/SuperStyleEngine.swift?
   - Recommendation: Put in Models/SuperTextStyle.swift. It is a pure value type (String, CaseIterable), fits Models/ layer. Engine in Core/ imports it. UI in Views/ imports it for segment control.

## Sources

### Primary (HIGH confidence)
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` -- full spec: styles, alias tables, bundleId mapping, gate design, postflight
- `Govorun/Models/ProductMode.swift` -- enum pattern reference (verified by reading source)
- `Govorun/Models/TextMode.swift` -- prompt generation pattern, systemPrompt/styleBlock structure (verified by reading source)
- `Govorun/Core/NormalizationGate.swift` -- LLMOutputContract definition (lines 5-8), caseless enum pattern (verified by reading source)
- `Govorun/Core/NormalizationPipeline.swift` -- DeterministicNormalizer, postflight, capitalize logic (verified by reading source)
- `Govorun/Core/AppContextEngine.swift` -- current bundleId mapping (verified by reading source)
- `GovorunTests/TestHelpers.swift` -- MockLLMClient pattern (verified by reading source)
- `GovorunTests/NormalizationGateTests.swift` -- test style reference (verified by reading source)
- `docs/canonical-style-spec.md` -- canonical forms spec (verified by reading source)

### Secondary (MEDIUM confidence)
- None needed -- all patterns come from existing codebase.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Swift enums, XCTest, Foundation. No external dependencies. Everything system-provided and verified installed (Xcode 26.4, Swift 6.3).
- Architecture: HIGH -- All file placements and patterns are locked decisions from CONTEXT.md, verified against existing codebase patterns.
- Pitfalls: HIGH -- Identified from reading the actual codebase; each pitfall maps to a concrete file/line that could cause the issue.

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (stable -- no external dependencies, all patterns from existing codebase)
