# Phase 4: Gate Modernization - Research

**Researched:** 2026-03-31
**Domain:** NormalizationGate style-awareness -- two-axis evaluate, alias-aware protected tokens, style-neutral edit distance, slang table
**Confidence:** HIGH

## Summary

Phase 4 transforms NormalizationGate from style-blind to style-aware. The gate currently validates LLM output using three checks: protected tokens (Latin words, URLs, emails, numbers, currencies must survive), edit distance (ratio of token changes must be below threshold), and basic guards (empty, refusal, length). All checks are style-agnostic -- any token change from Slack to "слак" counts as a missing protected token AND an edit distance change. This is the root cause of false rejections for relaxed/formal style transforms.

The fix is surgical: add `superStyle: SuperTextStyle?` parameter to `evaluate()`, then modify two internal functions. First, `missingProtectedTokens` learns that brand/tech aliases (in relaxed) and slang expansions (in formal) are equivalent forms -- if a protected token appears in ANY known alias form in the output, it passes. Second, `tokenizeForDistance` normalizes both input and output tokens to canonical forms before computing distance, making style transforms invisible to the edit distance check. A new `slangExpansions` table on `SuperTextStyle` (~15-20 pairs) provides the formal-style vocabulary, mirroring the existing `brandAliases`/`techTermAliases` pattern.

The existing architecture is extremely well suited for this. `NormalizationGate` is a caseless enum with static methods and private helpers -- no state, no protocols, no DI complexity. All 21 existing tests exercise the gate through the single `evaluate()` entry point. Phase 3 already wires `currentSuperStyle?.contract ?? .normalization` at both call sites in PipelineEngine -- Phase 4 only needs to add `superStyle:` to the gate signature and pass the value through.

**Primary recommendation:** Add `superStyle: SuperTextStyle? = nil` to `evaluate()`, build a unified alias lookup from existing brand/tech + new slang tables, modify `missingProtectedTokens` and `tokenizeForDistance` to be alias-aware, adjust `editDistanceThreshold` for relaxed/formal. Write TDD tests first for all style combinations.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Fixed table of ~15-20 slang pairs as `static let slangExpansions` on SuperTextStyle. Format: `[(slang: String, full: String)]`. Includes: норм->нормально, спс->спасибо, ок->хорошо, чё->что, щас->сейчас, инфа->информация, комп->компьютер, прога->программа, чел->человек etc. Concrete list determined at planning.
- **D-02:** Gate uses slang table only for validation in formal style -- both forms (slang and full) are valid protected tokens, normalizes to one form for edit distance.
- **D-03:** Before distance calculation, both texts are normalized: all known aliases (brand, tech, slang) replaced with canonical form. Style transforms = 0 edits.
- **D-04:** Canonical form -- original for brand/tech (Slack, PDF), full form for slang (спасибо, нормально).
- **D-05:** Relax thresholds for relaxed and formal -- additional margin on top of style-neutral normalization. Concrete values determined at planning.
- **D-06:** If protected token has a known alias (Slack<->слак, PDF<->пдф, спс<->спасибо), both forms are valid. Check: token present in output in ANY form -> ok.
- **D-07:** For tokens without alias (URL, email, numbers, unknown brands) -- check as before, unchanged.
- **D-08:** Conscious compromise: table covers top-25 brands + 4 tech terms + ~15-20 slang pairs. Unknown brands/slang handled by general edit distance (relaxed for relaxed/formal). Table expandable later without architectural changes.

### Claude's Discretion
- Concrete list of ~15-20 slang pairs (based on frequency in Russian conversational speech)
- Concrete values for relaxed thresholds for relaxed/formal
- Implementation of style-neutral normalization (separate function or inline in tokenizeForDistance)
- Order of checks in evaluate() (guard -> protected tokens -> distance)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GATE-01 | NormalizationGate.evaluate(input:output:contract:superStyle:) -- two axes | Current signature has `contract:` but no `superStyle:`. Add `superStyle: SuperTextStyle? = nil` -- default nil preserves backward compatibility. PipelineEngine already has `currentSuperStyle` at both call sites (lines 480, 621). |
| GATE-02 | Style-aware protected tokens: in relaxed both brand/tech alias forms valid | `protectedTokensForNormalization` extracts tokens via regex, `missingProtectedTokens` compares canonicalized forms. Need to expand comparison: if relaxed, check each expected token against alias table -- if alias exists and alias form found in output, token passes. |
| GATE-03 | Edit distance normalizes to style-neutral form before calculation | `tokenizeForDistance` already calls `canonicalize()` which lowercases. Add pre-step: replace known alias tokens with canonical form in both input and output before tokenization. Brand/tech -> original (Slack, PDF), slang -> full form (спасибо). |
| GATE-04 | In formal -- slang expansions (спс<->спасибо) valid as protected tokens | New `static let slangExpansions` on SuperTextStyle, same tuple format as brandAliases. Gate checks slang table when `superStyle == .formal`, both forms are valid. |
| TEST-04 | Unit tests NormalizationGate: style-aware protected tokens, slang, edit distance | 21 existing tests all pass through `evaluate()`. New tests add `superStyle:` parameter. Cover: relaxed brand alias accepted, relaxed tech alias accepted, formal slang accepted, nil style unchanged behavior, edit distance with style normalization for all three styles. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **No Co-Authored-By** -- public repo, no AI signs
- **TDD**: test (red) -> code (green) -> refactor
- **Core/ does not import SwiftUI or AppKit** -- NormalizationGate.swift is in Core/, pure Swift only
- **Models/ are pure value types** -- SuperTextStyle.swift is in Models/
- **Comments minimal, in Russian**
- **No force unwrap (!) in production code**
- **async/await, not completion handlers** -- though gate is synchronous (no async needed)
- **Commits in Russian**: `feat: добавить X`, `fix: исправить Y`
- **Protocols for DI** -- gate is a caseless enum, no protocol needed (established pattern)
- **Swift strict concurrency: complete** -- gate has no mutable state, all static methods (no concurrency concerns)

## Architecture Patterns

### Current Gate Structure (NormalizationGate.swift)

```
NormalizationGate (caseless enum)
├── evaluate()                          # PUBLIC: single entry point
│   ├── LLMResponseGuard.firstIssue()   # Step 1: empty/refusal/length guard
│   ├── evaluateNormalization()          # Step 2a: contract == .normalization
│   │   ├── protectedTokensForNormalization()  # Extract from input
│   │   ├── missingProtectedTokens()           # Compare input vs output tokens
│   │   ├── tokenizeForDistance()               # Tokenize both texts
│   │   ├── tokenEditDistance()                 # Levenshtein on token arrays
│   │   └── editDistanceThreshold()            # Adaptive threshold
│   └── evaluateRewriting()             # Step 2b: contract == .rewriting
│       ├── protectedTokensForNormalization()
│       ├── missingProtectedTokens()
│       └── length ratio check
└── private helpers
    ├── canonicalize()                   # lowercased + caseInsensitive + diacriticInsensitive
    ├── correctionAwareProtectedSource() # Self-correction marker handling
    ├── stripIgnoredLiterals()           # Remove snippet placeholders
    └── matches(of:in:)                 # Regex match extraction
```

### Modification Points (exactly 4 changes to existing code)

1. **`evaluate()` signature**: add `superStyle: SuperTextStyle? = nil`
2. **`missingProtectedTokens()`**: expand to check alias forms when superStyle is set
3. **`tokenizeForDistance()`**: add style-neutral normalization before tokenization
4. **`editDistanceThreshold()`**: add style-aware threshold relaxation

Plus 1 new addition to `SuperTextStyle.swift`:
5. **`static let slangExpansions`**: new table, same format as `brandAliases`

### Pattern: Unified Alias Lookup

Build a bidirectional lookup from all three tables for the style-aware checks:

```swift
// On NormalizationGate (private)
private static func styleAliases(
    for style: SuperTextStyle?
) -> [(canonical: String, variant: String)] {
    switch style {
    case .relaxed:
        // brand + tech: canonical = original (Slack), variant = relaxed (слак)
        return SuperTextStyle.brandAliases.map { (canonical: $0.original, variant: $0.relaxed) }
             + SuperTextStyle.techTermAliases.map { (canonical: $0.original, variant: $0.relaxed) }
    case .formal:
        // slang: canonical = full (спасибо), variant = slang (спс)
        return SuperTextStyle.slangExpansions.map { (canonical: $0.full, variant: $0.slang) }
    case .normal, nil:
        return []
    }
}
```

This lookup is used in two places:
- **Protected tokens**: if expected token (canonicalized) matches any known canonical OR variant form in output -> pass
- **Edit distance normalization**: replace variant tokens with canonical forms in both texts before tokenizing

### Anti-Patterns to Avoid

- **Modifying canonicalize()**: The existing `canonicalize()` is purely about case/diacritic normalization. Style-neutral normalization is a SEPARATE concern -- it replaces alias tokens, not characters. Do not conflate the two.
- **Building alias lookup on every evaluate() call**: The tables are static. Build lookup dictionaries lazily (private static let) for O(1) access, not on every call.
- **Checking aliases for tokens without aliases**: D-07 explicitly says tokens without known aliases (URLs, emails, numbers, unknown brands) check as before. The alias check is an ADDITIONAL pass that only applies to known aliases.
- **Mutating existing test assertions**: Existing 21 tests all pass `superStyle:` as nil (default). They MUST continue passing without changes. New style-aware tests are ADDITIONAL test methods.

## Standard Stack

No new dependencies. Everything is pure Swift in Core/ and Models/.

| Component | Location | Purpose |
|-----------|----------|---------|
| NormalizationGate | `Govorun/Core/NormalizationGate.swift` | Gate logic -- all changes here |
| SuperTextStyle | `Govorun/Models/SuperTextStyle.swift` | Add slangExpansions table here |
| NormalizationGateTests | `GovorunTests/NormalizationGateTests.swift` | New style-aware tests here |

### Existing Reusable Assets

| Asset | What it provides | How Phase 4 uses it |
|-------|-----------------|---------------------|
| `SuperTextStyle.brandAliases` | 25 `(original, relaxed)` pairs | Alias lookup for relaxed protected tokens + distance normalization |
| `SuperTextStyle.techTermAliases` | 4 `(original, relaxed)` pairs | Same as above |
| `NormalizationGate.canonicalize()` | lowercased + case/diacritic folding | Still the base token normalization; style normalization layers on top |
| `NormalizationGate.tokenizeForDistance()` | Split + punctuation trim + canonicalize | Hook point for pre-normalization of alias tokens |
| `NormalizationGate.editDistanceThreshold()` | Adaptive threshold (short/long/correction) | Extend with style-based relaxation |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Alias lookup structure | Custom hash map or nested loops on every call | Static lazy `[String: String]` dictionaries built from existing tables | O(1) per token, built once |
| Slang pair data | Hardcode inline in NormalizationGate | `static let slangExpansions` on SuperTextStyle (D-01) | Same pattern as brandAliases, extensible, single source of truth |
| Case-insensitive comparison | Manual lowercasing in alias checks | Existing `canonicalize()` applied to both sides before comparison | Already handles case + diacritics + Russian locale |

## Slang Expansions Table (Claude's Discretion)

Based on frequency in Russian conversational speech (typical voice dictation), recommended ~18 pairs:

| Slang | Full | Category |
|-------|------|----------|
| норм | нормально | evaluation |
| спс | спасибо | gratitude |
| ок | хорошо | agreement |
| чё | что | pronoun |
| щас | сейчас | temporal |
| инфа | информация | noun |
| комп | компьютер | tech noun |
| прога | программа | tech noun |
| чел | человек | noun |
| оч | очень | intensifier |
| пож | пожалуйста | politeness |
| тел | телефон | tech noun |
| мб | может быть | modal |
| плз | пожалуйста | politeness (alt) |
| норм | нормально | (covered above) |
| ладн | ладно | agreement |
| темп | температура | measurement |
| инет | интернет | tech noun |

Deduplicated list: 17 unique pairs. The format matches D-01: `[(slang: String, full: String)]`.

**Note on "ок"**: The slang "ок" expands to "хорошо" per D-01. However, "ок" is also a standalone legitimate word. In formal style, the LLM prompt says "сленг раскрывать" so the LLM WILL convert ок->хорошо. The gate must accept BOTH forms -- that is the point of D-06.

## Edit Distance Threshold Relaxation (Claude's Discretion)

Current thresholds in `editDistanceThreshold()`:
- **Short text** (<10 tokens): 0.25 (25%)
- **Long text** (>=10 tokens): 0.40 (40%)
- **Correction cue**: 0.80 (80%)

After style-neutral normalization, most style transforms should contribute 0 to edit distance. However, edge cases exist:
- Morphological changes from slang: "комп" (1 token) -> "компьютер" (1 token, different length but same token slot after normalization) -- covered by normalization
- The LLM may make non-alias style adjustments that the table does not cover (D-08)

Recommended relaxation:

| Style | Short (<10) | Long (>=10) | Rationale |
|-------|------------|-------------|-----------|
| nil (classic) | 0.25 | 0.40 | Unchanged |
| .normal | 0.25 | 0.40 | Unchanged -- normal has no style transforms |
| .relaxed | 0.35 | 0.50 | +0.10 buffer for edge-case brand forms not in table |
| .formal | 0.35 | 0.50 | +0.10 buffer for edge-case slang not in table |

The correction cue threshold (0.80) stays the same for all styles -- correction already allows massive changes.

**Reasoning for +0.10:** The style-neutral normalization handles known aliases (25 brands + 4 tech + 17 slang). The +0.10 buffer absorbs 1-2 additional unknown transforms in short text (1/10 = 0.10) or ~1 extra in long text. This is conservative enough to still catch hallucinations.

## Style-Neutral Normalization Implementation (Claude's Discretion)

Recommended: **separate private function** called before `tokenizeForDistance`.

```swift
/// Replace known alias tokens with their canonical forms.
/// Brand/tech: canonical = original (Slack, PDF)
/// Slang: canonical = full form (спасибо, нормально)
private static func normalizeStyleTokens(
    _ text: String,
    style: SuperTextStyle?
) -> String
```

Approach:
1. Build lazy static lookup dictionaries: `[canonicalized_variant: canonical_form]`
2. Split text into words
3. For each word, check canonicalized form against lookup
4. If found, replace with canonical form
5. Rejoin

This function is called on BOTH input and output text before `tokenizeForDistance`. The key insight: input text comes from DeterministicNormalizer which already converts brands to original form (слак -> Slack). But the LLM output for relaxed goes the OTHER way (Slack -> слак). The normalization brings both to the same form.

**Why a separate function (not inline in tokenizeForDistance):** `tokenizeForDistance` has a clear responsibility: split + trim + canonicalize. Style normalization is a higher-level concept (replace semantic aliases). Keeping them separate makes testing easier and follows the existing code's pattern of small, focused private functions.

## Common Pitfalls

### Pitfall 1: Alias Match Must Be Case-Insensitive
**What goes wrong:** Protected token check extracts "Slack" from input, looks for it in output. Output has "слак". Direct string comparison fails even though they are known aliases.
**Why it happens:** `canonicalize()` lowercases, but alias table has mixed case ("Slack", "слак"). Lookup must canonicalize both the token being checked AND the alias table entries.
**How to avoid:** Build the alias lookup dictionary with canonicalized keys. When checking a token, canonicalize it first, then look up.
**Warning signs:** Tests with "Slack" in input and "слак" in output fail the protected token check.

### Pitfall 2: Partial Word Matching in Distance Normalization
**What goes wrong:** Normalizing "слак" to "Slack" in the text also matches partial words like "подсказка" (contains "сказ" which is not "слак" but could be caught by naive replacement).
**Why it happens:** Naive `replacingOccurrences(of:)` without word boundaries.
**How to avoid:** The normalization operates on already-split tokens (words separated by whitespace), not on raw text. Each token is looked up as a whole word, not as a substring.
**Warning signs:** Unexpected replacements in words that contain alias substrings.

### Pitfall 3: Double Normalization
**What goes wrong:** DeterministicNormalizer already converts "слак" -> "Slack" in the input. If style-neutral normalization ALSO tries to normalize input, it would do nothing (since "Slack" is already canonical). But if we accidentally normalize output brands BACK to original AND the output already has original form, we might get confused.
**Why it happens:** Confusion about what each normalization layer does.
**How to avoid:** Style-neutral normalization normalizes variant -> canonical for BOTH texts. If a token is already in canonical form, the lookup simply does not find it in the variant->canonical map, leaving it unchanged. This is idempotent by design.
**Warning signs:** None -- the design naturally handles this.

### Pitfall 4: Protected Token Check for Slang in Non-Formal Styles
**What goes wrong:** Slang aliases are only relevant for formal style (D-02). If the check applies slang aliases to relaxed style, it would incorrectly accept "спасибо" as a valid form of "спс" in relaxed output.
**Why it happens:** Not scoping the alias table to the correct style.
**How to avoid:** The `styleAliases(for:)` function returns ONLY the aliases relevant to the current style. Relaxed gets brand+tech, formal gets slang, normal/nil gets nothing.
**Warning signs:** Tests where relaxed style incorrectly accepts slang transforms.

### Pitfall 5: Backward Compatibility -- nil superStyle Must Not Change Behavior
**What goes wrong:** Adding superStyle parameter changes behavior for existing (non-style) paths.
**Why it happens:** Default parameter value not set, or alias lookup returns results for nil style.
**How to avoid:** `superStyle: SuperTextStyle? = nil` default. `styleAliases(for: nil)` returns empty array. All existing tests pass without modification.
**Warning signs:** Any of the existing 21 tests fail after the change.

### Pitfall 6: NormalizationPipeline.postflight Also Calls Gate
**What goes wrong:** Forgetting that NormalizationPipeline.postflight() in NormalizationPipeline.swift calls NormalizationGate.evaluate() and also needs `superStyle:` parameter.
**Why it happens:** Two call sites: PipelineEngine.swift (line 477, snippet path) and NormalizationPipeline.swift (line 639, postflight path).
**How to avoid:** Add `superStyle:` parameter to postflight() signature as well. PipelineEngine.swift already has `currentSuperStyle` available.
**Warning signs:** Compiler error if evaluate() signature changes but postflight() does not pass the new parameter.

## Code Examples

### Example 1: Gate Signature Change

```swift
// Before (current)
static func evaluate(
    input: String,
    output: String,
    contract: LLMOutputContract,
    ignoredOutputLiterals: Set<String> = []
) -> NormalizationGateResult

// After
static func evaluate(
    input: String,
    output: String,
    contract: LLMOutputContract,
    superStyle: SuperTextStyle? = nil,
    ignoredOutputLiterals: Set<String> = []
) -> NormalizationGateResult
```

### Example 2: Alias-Aware Protected Token Check

```swift
// Current missingProtectedTokens check:
// expected.filter { !actualCanonical.contains(canonicalize($0)) }

// Style-aware: for each expected token, check if it OR any alias form exists in output
private static func missingProtectedTokens(
    expected: [String],
    actualText: String,
    ignoredOutputLiterals: Set<String>,
    superStyle: SuperTextStyle?
) -> [String] {
    let actualCanonical = Set(
        extractProtectedTokens(from: actualText, ignoredLiterals: ignoredOutputLiterals)
    )
    let aliasLookup = buildAliasLookup(for: superStyle) // [canonicalized_form: canonicalized_canonical]

    return expected.filter { token in
        let canonToken = canonicalize(token)
        // Direct match
        if actualCanonical.contains(canonToken) { return false }
        // Alias match: check if canonical form of the alias is in output
        if let canonical = aliasLookup[canonToken],
           actualCanonical.contains(canonical) { return false }
        // Reverse: check if token IS the canonical and variant is in output
        // (handled by building lookup in both directions)
        return true
    }
}
```

### Example 3: Style-Neutral Token Normalization

```swift
// Normalize alias tokens to canonical form before distance calculation
private static func normalizeStyleTokens(
    _ tokens: [String],
    style: SuperTextStyle?
) -> [String] {
    guard let style = style, style != .normal else { return tokens }
    let lookup = styleNormalizationLookup(for: style) // [canonicalized_variant: canonicalized_canonical]
    return tokens.map { token in
        lookup[token] ?? token // token is already canonicalized by tokenizeForDistance
    }
}
```

### Example 4: Slang Table on SuperTextStyle

```swift
// In SuperTextStyle.swift, mirrors brandAliases pattern
static let slangExpansions: [(slang: String, full: String)] = [
    ("норм", "нормально"),
    ("спс", "спасибо"),
    ("ок", "хорошо"),
    ("чё", "что"),
    ("щас", "сейчас"),
    ("инфа", "информация"),
    ("комп", "компьютер"),
    ("прога", "программа"),
    ("чел", "человек"),
    ("оч", "очень"),
    ("пож", "пожалуйста"),
    ("тел", "телефон"),
    ("мб", "может быть"),
    ("плз", "пожалуйста"),
    ("ладн", "ладно"),
    ("темп", "температура"),
    ("инет", "интернет"),
]
```

### Example 5: Test for Relaxed Brand Alias Protected Token

```swift
func test_relaxed_accepts_brand_alias_as_protected_token() {
    // Input has "Slack" (Latin, protected), output has "слак" (Cyrillic alias)
    let result = NormalizationGate.evaluate(
        input: "Скинь в Slack.",
        output: "скинь в слак",
        contract: .normalization,
        superStyle: .relaxed
    )

    XCTAssertTrue(result.accepted)
}
```

### Example 6: Test for Formal Slang Protected Token

```swift
func test_formal_accepts_slang_expansion_as_protected_token() {
    // Input has "спс" (slang), output has "спасибо" (expanded)
    let result = NormalizationGate.evaluate(
        input: "Спс за помощь.",
        output: "Спасибо за помощь.",
        contract: .normalization,
        superStyle: .formal
    )

    XCTAssertTrue(result.accepted)
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, Xcode 15.4) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GATE-01 | evaluate() accepts superStyle parameter, nil default preserves old behavior | unit | `xcodebuild test ... -only-testing:GovorunTests/NormalizationGateTests` | Existing tests verify nil behavior; new tests for non-nil -- Wave 0 |
| GATE-02 | Relaxed: both brand/tech alias forms valid as protected tokens | unit | same | Wave 0 |
| GATE-03 | Edit distance normalizes to style-neutral form | unit | same | Wave 0 |
| GATE-04 | Formal: slang expansions valid as protected tokens | unit | same | Wave 0 |
| TEST-04 | Unit tests cover style-aware tokens, slang, edit distance for all 3 styles | unit | same | Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateTests` (~2 sec)
- **Per wave merge:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` (full suite, ~30 sec)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New test methods in `GovorunTests/NormalizationGateTests.swift` -- covers GATE-01 through GATE-04, TEST-04
- [ ] `SuperTextStyle.slangExpansions` table in `Govorun/Models/SuperTextStyle.swift` -- data prerequisite for GATE-04

No framework install needed -- XCTest is built-in. No new test files needed -- existing `NormalizationGateTests.swift` is the right home.

## Call Sites That Must Change

| Location | Current | After Phase 4 |
|----------|---------|---------------|
| `NormalizationGate.evaluate()` signature (line 129) | `contract:, ignoredOutputLiterals:` | `contract:, superStyle:, ignoredOutputLiterals:` |
| `NormalizationGate.evaluateNormalization()` (line 165) | No style awareness | Passes superStyle to `missingProtectedTokens` and `tokenizeForDistance` flow |
| `NormalizationGate.evaluateRewriting()` (line 210) | No style awareness | Passes superStyle to `missingProtectedTokens` (distance not relevant) |
| `NormalizationGate.missingProtectedTokens()` (line 270) | Exact canonical match only | Alias-aware match: canonical OR any alias form |
| `NormalizationGate.tokenizeForDistance()` (line 346) | No pre-normalization | Normalize alias tokens to canonical form before tokenization |
| `NormalizationGate.editDistanceThreshold()` (line 313) | Style-blind | Style-aware thresholds (D-05) |
| `NormalizationPipeline.postflight()` (line 629) | No superStyle param | Add `superStyle:` param, pass to `evaluate()` |
| `PipelineEngine` snippet path (line 477) | Passes `contract:` only | Add `superStyle: currentSuperStyle` |
| `PipelineEngine` postflight path (line 618) | Passes `contract:` only | Add `superStyle: currentSuperStyle` |

**Total production files changed: 3** (NormalizationGate.swift, SuperTextStyle.swift, NormalizationPipeline.swift)
**PipelineEngine.swift:** Only needs to add `superStyle:` parameter to 2 call sites -- minimal touch.
**Total test files changed: 1** (NormalizationGateTests.swift)

## Open Questions

1. **NormalizationPipeline.postflight tests**
   - What we know: `NormalizationPipelineTests.swift` has 8 tests that call `postflight()`. When postflight gets a new `superStyle:` parameter, these tests need updating.
   - What's unclear: Whether to add `superStyle: nil` explicitly to existing tests or rely on default parameter.
   - Recommendation: Use default parameter `superStyle: SuperTextStyle? = nil` so existing tests compile unchanged. Add new postflight tests only if needed for integration coverage (gate tests are the primary coverage).

2. **"мб" slang expansion to "может быть"**
   - What we know: "мб" -> "может быть" is a multi-word expansion. Single token becomes two tokens.
   - What's unclear: Whether this causes issues with token-level edit distance comparison.
   - Recommendation: In the normalization step, the single token "мб" is replaced by "может быть" (2 tokens). This is fine because the SAME replacement happens to both input and output. If input has "мб" and output has "может быть", after normalization both become "может быть" -- distance = 0. If input has "может быть" already, normalization leaves it unchanged, and output's "может быть" matches. No issue.

## Sources

### Primary (HIGH confidence)
- `Govorun/Core/NormalizationGate.swift` -- full file read, all methods analyzed
- `Govorun/Models/SuperTextStyle.swift` -- full file read, alias tables confirmed (25 brand + 4 tech)
- `GovorunTests/NormalizationGateTests.swift` -- full file read, 21 tests all passing
- `GovorunTests/NormalizationPipelineTests.swift` -- full file read, 8 tests confirmed
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` lines 52-74 -- spec for gate two-axis design
- `Govorun/Core/PipelineEngine.swift` lines 477, 618 -- both gate call sites confirmed
- `Govorun/Core/NormalizationPipeline.swift` lines 629-644 -- postflight gate call site confirmed
- `.planning/phases/04-gate-modernization/04-CONTEXT.md` -- all 8 locked decisions + discretion areas
- `.planning/phases/03-pipeline-integration/03-VERIFICATION.md` -- Phase 3 verified complete, `currentSuperStyle` wired

### Secondary (MEDIUM confidence)
- Slang frequency in Russian speech -- based on common Russian internet/messaging abbreviations; specific pairs may need tuning based on real voice input data
- Threshold relaxation values (+0.10) -- heuristic based on table coverage analysis; may need empirical adjustment

## Metadata

**Confidence breakdown:**
- Gate architecture understanding: HIGH -- full source read, all methods traced, all call sites identified
- Modification strategy: HIGH -- changes are surgical, well-bounded, compiler-verified
- Slang table content: MEDIUM -- based on common Russian abbreviations, not empirical voice data
- Threshold values: MEDIUM -- heuristic, may need tuning after integration testing
- Test coverage plan: HIGH -- follows existing test patterns, clear test matrix

**Research date:** 2026-03-31
**Valid until:** Indefinite (internal codebase, no external dependency drift)
