# Phase 9: TextMode Deletion -- Research

**Researched:** 2026-04-02
**Phase goal:** TextMode и вся его инфраструктура удалены -- единственная система стилей в проекте это SuperTextStyle

## 1. Files to Delete (Full Analysis)

### 1.1 `Govorun/Models/TextMode.swift` (188 lines)

**Defines:**
- `enum TextMode: String, CaseIterable, Codable` with cases: `.chat`, `.email`, `.document`, `.note`, `.code`, `.universal`
- `extension TextMode` with:
  - `static func basePrompt(currentDate:personalDictionary:) -> String` -- the full base system prompt (~83 lines of Russian prompt text)
  - `var styleBlock: String` -- per-mode style instructions
  - `func systemPrompt(currentDate:personalDictionary:snippetContext:appName:) -> String` -- combines base + style + context

**Depends on (imports):**
- `Foundation`
- `SnippetContext` (from `Models/SnippetContext.swift`)
- `SnippetPlaceholder.token` (from `Models/SnippetPlaceholder.swift`)

**Depended on by (production code):**
- `Govorun/Core/AppContextEngine.swift` -- `AppContext.textMode: TextMode`, `defaultAppModes: [String: TextMode]`, `resolveTextMode() -> TextMode`, `textMode(for:) -> TextMode`
- `Govorun/Core/NormalizationGate.swift` lines 10-17 -- `extension TextMode { var llmOutputContract: LLMOutputContract }`
- `Govorun/Views/AppModeSettingsView.swift` -- uses `TextMode` extensively
- `Govorun/App/AppState.swift` line 862 -- `context.textMode.rawValue`
- `scripts/benchmark-full-pipeline-helper.swift` -- `parseTextMode()`, `textMode.systemPrompt()`, `textMode` in postflight

**Depended on by (tests):**
- `GovorunTests/AppContextEngineTests.swift` -- `context.textMode` assertions throughout (lines 66, 78, 90, 102, 114, 127, 202, 216, 228, 240, 252, 260-263, 275, 279, 292), `engine.textMode(for:)` calls
- `GovorunTests/HistoryStoreTests.swift` -- `AppContext(..., textMode: .chat)` at lines 43, 179

**Note:** `SuperTextStyle.swift` already has its own `basePrompt`, `styleBlock`, and `systemPrompt()` -- these are NOT copies from TextMode. TextMode's prompt code is dead for the pipeline (replaced in Phase 3).

### 1.2 `Govorun/Views/AppModeSettingsView.swift` (181 lines)

**Defines:**
- `struct AppModeSettingsView: View` -- UI for per-app TextMode overrides
- `private struct ModePicker: View` -- dropdown for TextMode selection
- `struct AppModeEntry: Identifiable` -- model with `bundleId: String`, `mode: TextMode`

**Depends on:**
- `SwiftUI`
- `TextMode` enum
- `AppModeOverriding` protocol
- `UserDefaultsAppModeOverrides` class
- UI components from `SettingsTheme.swift` (`BrandedEmptyState`, `SectionHeader`, `AddButton`, `.settingsCard()`)

**Depended on by:**
- `Govorun/Views/SettingsView.swift` line 23 -- `case .appModes: AppModeSettingsView()`

### 1.3 `Govorun/App/NSWorkspaceProvider.swift` (37 lines)

**Defines:**
- `final class NSWorkspaceProvider: WorkspaceProviding` -- returns frontmost app bundleId/appName via `NSWorkspace.shared`
- `final class UserDefaultsAppModeOverrides: AppModeOverriding` -- UserDefaults-backed per-app mode overrides

**Depends on:**
- `Cocoa`
- `WorkspaceProviding` protocol (defined in `AppContextEngine.swift`)
- `AppModeOverriding` protocol (defined in `AppContextEngine.swift`)

**Depended on by:**
- `Govorun/App/AppState.swift` lines 113-114 (production init params), lines 255-256 (test init default)
- `AppModeSettingsView` (being deleted anyway)

**CRITICAL:** `NSWorkspaceProvider` contains the `WorkspaceProviding` implementation that provides `bundleId` detection. After deleting this file, `AppContextEngine` still needs workspace access. The `WorkspaceProviding` protocol and `NSWorkspaceProvider` class MUST be preserved or inlined -- bundleId detection is used by `SuperStyleEngine.resolve(bundleId:...)`.

**Decision from CONTEXT.md D-03:** `NSWorkspaceProvider.swift` is listed for full deletion. But per D-04, `bundleId` detection must stay. This means either:
- (a) Inline `NSWorkspaceProvider` into `AppContextEngine.swift` (since WorkspaceProviding protocol is already there), OR
- (b) Keep `NSWorkspaceProvider.swift` but only with `NSWorkspaceProvider` class (delete `UserDefaultsAppModeOverrides`)

The CONTEXT.md lists NSWorkspaceProvider.swift for full deletion (D-03), but also says bundleId detection stays (D-04). Resolution: `NSWorkspaceProvider` class must be preserved somewhere. The cleanest approach: move `NSWorkspaceProvider` into `AppContextEngine.swift` alongside the `WorkspaceProviding` protocol it implements, then delete `NSWorkspaceProvider.swift`.

## 2. Surgical Edits Required

### 2.1 `Govorun/Core/AppContextEngine.swift` (99 lines -> ~30 lines)

**Current structure (line-by-line):**
- Lines 1: `import Foundation`
- Lines 3-4: `// MARK: - AppContext`
- Lines 5-9: `struct AppContext: Equatable { bundleId, appName, textMode }`
- Lines 11-14: `protocol WorkspaceProviding`
- Lines 17-23: `protocol AppModeOverriding` -- DELETE entirely
- Lines 25-57: `private let defaultAppModes: [String: TextMode]` -- DELETE entirely
- Lines 59-99: `final class AppContextEngine` -- MODIFY

**Changes:**
1. **Line 8:** Remove `let textMode: TextMode` from `AppContext` struct. Struct becomes `{ bundleId: String, appName: String }`.
2. **Lines 17-23:** Delete `protocol AppModeOverriding` entirely (3 methods).
3. **Lines 25-57:** Delete `private let defaultAppModes` dictionary entirely (30 lines).
4. **Line 63:** Remove `private let modeOverrides: AppModeOverriding` property.
5. **Line 65:** Simplify init to `init(workspace: WorkspaceProviding)` -- remove `modeOverrides` param.
6. **Lines 70-81:** Simplify `detectCurrentApp()` -- remove `resolveTextMode(for:)` call, remove `textMode: mode` from AppContext construction.
7. **Lines 83-85:** Delete `func textMode(for:) -> TextMode` entirely.
8. **Lines 89-98:** Delete `private func resolveTextMode(for:) -> TextMode` entirely.
9. **Add:** `NSWorkspaceProvider` class (from deleted `NSWorkspaceProvider.swift`) -- 5 lines.

**What stays:**
- `struct AppContext` (without textMode)
- `protocol WorkspaceProviding`
- `class AppContextEngine` with `workspace` property and `detectCurrentApp()` returning bundleId/appName
- `NSWorkspaceProvider` class (moved here from deleted file)

### 2.2 `Govorun/Core/NormalizationGate.swift` -- lines 10-17

**Remove:**
```swift
extension TextMode {
    /// Пока в продукте нет отдельного пользовательского режима
    /// «как сказал / чисто / формально», все app-aware режимы идут
    /// через контракт нормализации. Rewriting останется для следующего этапа.
    var llmOutputContract: LLMOutputContract {
        .normalization
    }
}
```

This is dead code -- the pipeline already uses `SuperTextStyle.contract` (Phase 3 migrated this). Remove lines 10-17 inclusive.

**Everything else in this file stays** (496 lines - 8 lines = 488 lines).

### 2.3 `Govorun/App/AppState.swift` -- 4 edit locations

**Edit 1 -- Production init params (lines 113-114):**
```swift
// REMOVE these two parameters:
workspace: WorkspaceProviding = NSWorkspaceProvider(),
modeOverrides: AppModeOverriding = UserDefaultsAppModeOverrides(),
```

**Edit 2 -- Production init body (lines 182-185):**
```swift
// CHANGE FROM:
appContextEngine = AppContextEngine(
    workspace: workspace,
    modeOverrides: modeOverrides
)
// TO:
appContextEngine = AppContextEngine(workspace: NSWorkspaceProvider())
```

**Edit 3 -- Test init default (lines 254-257):**
```swift
// CHANGE FROM:
self.appContextEngine = appContextEngine ?? AppContextEngine(
    workspace: NSWorkspaceProvider(),
    modeOverrides: UserDefaultsAppModeOverrides()
)
// TO:
self.appContextEngine = appContextEngine ?? AppContextEngine(
    workspace: NSWorkspaceProvider()
)
```

**Edit 4 -- Analytics metadata (line 862):**
```swift
// REMOVE this line:
AnalyticsMetadataKey.textMode: context.textMode.rawValue,
```

### 2.4 `Govorun/Models/AnalyticsEvent.swift` -- line 57

**Remove:**
```swift
static let textMode = "text_mode"
```

### 2.5 `Govorun/Views/HistoryView.swift` -- line 112

**No change needed.** Line 112 reads:
```swift
if let styleName = SuperTextStyle(rawValue: item.textMode)?.displayName {
```
This uses `item.textMode` (a String property on `HistoryItem` -- NOT the `TextMode` enum). `SuperTextStyle(rawValue:)` returns nil for old TextMode values like "chat"/"email", so legacy entries show no badge. This is the correct behavior per D-05.

### 2.6 `Govorun/Views/SettingsTheme.swift` -- `case appModes`

**Remove from `SettingsSection` enum:**
- Line 22: `case appModes // Скрыт до Фазы 5 (LocalLLMClient) -- TextMode без LLM не работает`
- Line 32: Remove comment `/// Секции видимые в UI (appModes скрыт до Фазы 5)` or update
- Line 38: `case .appModes: "Приложения"`
- Line 49: `case .appModes: "Настройка режимов для конкретных приложений"`
- Line 60: `case .appModes: "app.badge"`

Note: `visibleCases` (line 33) does NOT include `.appModes`, so removing it won't affect the sidebar. But the switch statements in `title`, `subtitle`, and `icon` must have the case removed.

### 2.7 `Govorun/Views/SettingsView.swift` -- lines 22-23

**Remove:**
```swift
case .appModes:
    AppModeSettingsView()
```

After removing `case appModes` from the enum, the compiler will catch this -- but it must be removed or the switch won't compile.

### 2.8 `Govorun/Storage/HistoryStore.swift` -- NO CHANGES

Per D-06, the save function continues writing `result.superStyle?.rawValue ?? "none"` to the `textMode` field. No change needed.

### 2.9 `Govorun/Models/HistoryItem.swift` -- NO CHANGES

Per D-07, the `textMode: String` field stays for backward compatibility. No SwiftData migration.

## 3. Full Dependency Graph

### 3.1 Production code referencing TextMode/related symbols

| File | Symbol(s) | Action |
|------|-----------|--------|
| `Govorun/Models/TextMode.swift` | `enum TextMode`, `basePrompt`, `styleBlock`, `systemPrompt` | DELETE file |
| `Govorun/Views/AppModeSettingsView.swift` | `TextMode`, `AppModeOverriding`, `UserDefaultsAppModeOverrides` | DELETE file |
| `Govorun/App/NSWorkspaceProvider.swift` | `NSWorkspaceProvider`, `UserDefaultsAppModeOverrides` | DELETE file (move NSWorkspaceProvider) |
| `Govorun/Core/AppContextEngine.swift` | `TextMode`, `AppModeOverriding`, `defaultAppModes`, `resolveTextMode` | EDIT (major refactor) |
| `Govorun/Core/NormalizationGate.swift` | `extension TextMode { llmOutputContract }` | EDIT (delete 8 lines) |
| `Govorun/App/AppState.swift` | `WorkspaceProviding`, `NSWorkspaceProvider`, `AppModeOverriding`, `UserDefaultsAppModeOverrides`, `context.textMode.rawValue` | EDIT (4 locations) |
| `Govorun/Models/AnalyticsEvent.swift` | `AnalyticsMetadataKey.textMode` | EDIT (delete 1 line) |
| `Govorun/Views/SettingsTheme.swift` | `case appModes` | EDIT (delete case from enum + switches) |
| `Govorun/Views/SettingsView.swift` | `case .appModes: AppModeSettingsView()` | EDIT (delete 2 lines) |

### 3.2 Files that reference `textMode` as a String field (NO CHANGES)

| File | Usage | Action |
|------|-------|--------|
| `Govorun/Models/HistoryItem.swift` | `var textMode: String` stored property | KEEP (D-07) |
| `Govorun/Storage/HistoryStore.swift` | `textMode: result.superStyle?.rawValue ?? "none"` | KEEP (D-06) |
| `Govorun/Views/HistoryView.swift` | `SuperTextStyle(rawValue: item.textMode)?.displayName` | KEEP (D-05) |

### 3.3 Files already clean (no TextMode references)

Verified zero references in:
- `Govorun/Core/PipelineEngine.swift` -- migrated in Phase 3
- `Govorun/Core/NormalizationPipeline.swift` -- migrated in Phase 3
- `Govorun/Services/LLMClient.swift` -- migrated in Phase 3
- `Govorun/Services/LocalLLMClient.swift` -- migrated in Phase 3
- `GovorunTests/TestHelpers.swift` -- migrated in Phase 3
- `GovorunTests/PipelineEngineTests.swift` -- migrated in Phase 3
- `GovorunTests/NormalizationPipelineTests.swift` -- migrated in Phase 3

### 3.4 Scripts and benchmarks

| File | Reference | Action |
|------|-----------|--------|
| `scripts/benchmark-full-pipeline-helper.swift` | `TextMode` enum, `parseTextMode()`, `textMode.systemPrompt()`, `textMode` in postflight call | OUT OF SCOPE (benchmark script, not production) |
| `scripts/benchmark-llm-normalization.py` | `TextMode.swift` in HELPER_SWIFT_SOURCES, `--text-mode` arg, `textMode` in request JSON | OUT OF SCOPE (benchmark script) |

**Note:** The benchmark helper script (`benchmark-full-pipeline-helper.swift`) directly compiles `TextMode.swift` as one of its source files. After deleting `TextMode.swift`, the benchmark will fail to build. This needs to be either:
- Updated to use `SuperTextStyle` instead (separate task, not blocking Phase 9), OR
- Documented as known breakage for planner to decide

### 3.5 Documentation referencing TextMode

| File | Action |
|------|--------|
| `docs/architecture.md` line 73 | Update (remove TextMode.swift from tree) |
| `benchmarks/README.md` line 76 | Update (TextMode -> SuperTextStyle) |
| `benchmarks/reports/*.md` | Informational only, no code changes |
| `CLAUDE.md` lines 114, 366-369 | Update (GSD-injected sections from PROJECT.md/ARCHITECTURE.md) |

## 4. Test Impact Analysis

### 4.1 `GovorunTests/AppContextEngineTests.swift` (294 lines) -- MAJOR REWRITE

**Contains:**
- `MockWorkspaceProvider` class (lines 6-13) -- KEEP (still needed for testing workspace)
- `MockAppModeOverrides` class (lines 17-31) -- DELETE entirely
- `AppContextEngineTests` class (lines 35-294) with `makeEngine()` helper and 18 test functions

**Tests that use `context.textMode` (DELETE or REWRITE):**
- `test_telegram_detected_as_chat` -- asserts `context.textMode == .chat` (line 66)
- `test_mail_detected_as_email` -- asserts `context.textMode == .email` (line 78)
- `test_chrome_detected_as_universal` -- asserts `context.textMode == .universal` (line 90)
- `test_safari_detected_as_universal` -- asserts `context.textMode == .universal` (line 102)
- `test_unknown_app_is_universal` -- asserts `context.textMode == .universal` (line 114)
- `test_user_override_respected` -- asserts `context.textMode == .email` with override (line 127)
- `test_nil_bundle_id_is_universal` -- asserts `context.textMode == .universal` (line 202)
- `test_slack_detected_as_chat` -- asserts `context.textMode == .chat` (line 216)
- `test_vscode_detected_as_code` -- asserts `context.textMode == .code` (line 228)
- `test_notes_detected_as_note` -- asserts `context.textMode == .note` (line 240)
- `test_pages_detected_as_document` -- asserts `context.textMode == .document` (line 252)
- `test_textMode_for_known_bundleId` -- calls `engine.textMode(for:)` (lines 257-263)
- `test_override_takes_priority_over_default` -- asserts textMode with/without override (lines 268-280)
- `test_invalid_override_falls_back_to_default` -- asserts textMode fallback (lines 284-293)

**Tests that survive with modification:**
- `test_prompt_varies_by_mode` (line 132) -- already uses `SuperTextStyle`, KEEP
- `test_relaxed_style_uses_conversational_register` (line 143) -- already uses `SuperTextStyle`, KEEP
- `test_formal_style_uses_business_register` (line 150) -- already uses `SuperTextStyle`, KEEP
- `test_prompt_includes_current_date` (line 157) -- already uses `SuperTextStyle`, KEEP
- `test_prompt_preserves_command_frame_examples` (line 168) -- already uses `SuperTextStyle`, KEEP
- `test_prompt_includes_anti_paraphrase_long_form_examples` (line 177) -- already uses `SuperTextStyle`, KEEP
- `test_prompt_correction_examples_preserve_explicit_time_of_day` (line 186) -- already uses `SuperTextStyle`, KEEP

**After rewrite:**
- `makeEngine()` helper: remove `overrides` parameter, remove `MockAppModeOverrides` usage. Init `AppContextEngine(workspace:)` only.
- Tests 1-6, 11-18: Either delete entirely (TextMode mapping tests are no longer relevant) or rewrite to test bundleId/appName detection only.
- Tests 7-10 + prompt tests: Already migrated to `SuperTextStyle` -- KEEP as-is, possibly move to `SuperTextStyleTests.swift` if they don't test `AppContextEngine`.

**Recommended approach:** Delete all tests that assert `context.textMode`. Keep tests that verify bundleId/appName detection (tests 1, 4, 5, 11). Keep all SuperTextStyle prompt tests. Delete `MockAppModeOverrides`.

### 4.2 `GovorunTests/HistoryStoreTests.swift` -- MINOR EDIT

**Affected lines:**
- Line 43: `AppContext(bundleId: bundleId, appName: appName, textMode: .chat)` -- remove `textMode:` parameter
- Line 179: `AppContext(bundleId: "", appName: "", textMode: .universal)` -- remove `textMode:` parameter
- Line 68: `XCTAssertEqual(item.textMode, "normal")` -- this tests the STRING field on HistoryItem, NOT the TextMode enum. KEEP.

**Changes:** Update `makeAppContext()` helper and inline `AppContext(...)` construction to match new 2-field struct.

### 4.3 `GovorunTests/IntegrationTests.swift` -- MINOR EDIT

**Affected lines:**
- Line 82: `let mockWorkspace = MockWorkspaceProvider()` -- KEEP (MockWorkspaceProvider stays)
- Line 85-88: `AppContextEngine(workspace: mockWorkspace, modeOverrides: MockAppModeOverrides())` -- remove `modeOverrides:` parameter

### 4.4 Other test files -- NO CHANGES

All of the following were verified to have zero TextMode references:
- `TestHelpers.swift`, `PipelineEngineTests.swift`, `NormalizationPipelineTests.swift`
- `NormalizationGateTests.swift`, `SnippetEngineTests.swift`, `LocalLLMClientTests.swift`
- `SettingsStoreTests.swift`, `AnalyticsServiceTests.swift`
- All other 24 test files in `GovorunTests/`

## 5. Build System Impact

### 5.1 project.yml

Verified: `project.yml` does NOT contain `TextMode`, `AppModeSettingsView`, or `NSWorkspaceProvider`. XcodeGen uses glob patterns for sources (`Govorun/**/*.swift`), so deleting .swift files does not require `project.yml` changes.

### 5.2 Xcode project

`Govorun.xcodeproj/project.pbxproj` contains references to `TextMode.swift` (lines 113, 191, 325, 694). Running `xcodegen generate` will regenerate the project file from `project.yml` and automatically exclude deleted files. This is a **required step** after deleting files.

### 5.3 Build command

```bash
xcodegen generate && xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation
```

## 6. Deletion Order & Safety

### Recommended order of operations:

**Step 1: Surgical edits to production code (order matters for compilation)**

1. `AppContextEngine.swift` -- Remove `textMode` from `AppContext`, delete `AppModeOverriding` protocol, `defaultAppModes`, `resolveTextMode()`, `textMode(for:)`. Add `NSWorkspaceProvider` class. Simplify init.
2. `NormalizationGate.swift` -- Delete `extension TextMode { llmOutputContract }` (lines 10-17)
3. `AppState.swift` -- Remove `modeOverrides` param, simplify `AppContextEngine` init calls, remove `context.textMode.rawValue` from analytics
4. `AnalyticsEvent.swift` -- Delete `static let textMode`
5. `SettingsTheme.swift` -- Delete `case appModes` and all switch branches
6. `SettingsView.swift` -- Delete `case .appModes: AppModeSettingsView()`

**Step 2: Delete files**

7. `git rm Govorun/Models/TextMode.swift`
8. `git rm Govorun/Views/AppModeSettingsView.swift`
9. `git rm Govorun/App/NSWorkspaceProvider.swift`

**Step 3: Regenerate and compile**

10. `xcodegen generate`
11. `xcodebuild build` -- compilation checkpoint

**Step 4: Test edits**

12. `AppContextEngineTests.swift` -- Delete `MockAppModeOverrides`, delete TextMode-assertion tests, update `makeEngine()`, keep SuperTextStyle prompt tests
13. `HistoryStoreTests.swift` -- Update `makeAppContext()` helper, update inline `AppContext(...)` calls
14. `IntegrationTests.swift` -- Remove `MockAppModeOverrides()` from `AppContextEngine` init

**Step 5: Full test run**

15. `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`

## 7. Validation Architecture

### 7.1 Zero-reference verification

```bash
# After all changes, before commit:
grep -rn "TextMode" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results

grep -rn "AppModeOverriding" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results

grep -rn "UserDefaultsAppModeOverrides" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results

grep -rn "defaultAppModes" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results

grep -rn "resolveTextMode" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results

grep -rn "AppModeSettingsView" --include="*.swift" Govorun/ GovorunTests/
# Expected: ZERO results
```

### 7.2 Allowed residuals (NOT errors)

```bash
grep -rn "textMode" --include="*.swift" Govorun/ GovorunTests/
# ALLOWED matches (String field, not TextMode enum):
#   HistoryItem.swift: var textMode: String
#   HistoryStore.swift: textMode: result.superStyle?.rawValue ?? "none"
#   HistoryView.swift: SuperTextStyle(rawValue: item.textMode)?.displayName
#   HistoryStoreTests.swift: XCTAssertEqual(item.textMode, "normal") (String assertion)
```

### 7.3 Build + test commands

```bash
xcodegen generate
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation
```

### 7.4 File existence check

```bash
# These files must NOT exist after Phase 9:
test ! -f Govorun/Models/TextMode.swift
test ! -f Govorun/Views/AppModeSettingsView.swift
test ! -f Govorun/App/NSWorkspaceProvider.swift
```

## 8. Risk Assessment

### 8.1 HIGH: NSWorkspaceProvider preservation

**Risk:** Deleting `NSWorkspaceProvider.swift` removes the `WorkspaceProviding` conformance that `AppContextEngine` needs for bundleId detection. Without it, `SuperStyleEngine.resolve(bundleId:...)` gets no bundleId and auto-mode breaks.

**Mitigation:** Move `NSWorkspaceProvider` class into `AppContextEngine.swift` (alongside the `WorkspaceProviding` protocol it implements) before deleting the file. Alternatively keep it in its own file -- but CONTEXT.md D-03 says delete the file.

### 8.2 MEDIUM: Benchmark script breakage

**Risk:** `scripts/benchmark-full-pipeline-helper.swift` directly compiles `TextMode.swift` as a source dependency. After deletion, `swiftc` compilation of the benchmark helper will fail. `benchmark-llm-normalization.py` references the file path in `HELPER_SWIFT_SOURCES`.

**Mitigation:** This is OUT OF SCOPE for Phase 9 (benchmarks are not production code and not part of the test suite). Document as known breakage. A follow-up task can migrate the benchmark to use `SuperTextStyle`.

### 8.3 MEDIUM: AppContextEngineTests rewrite scope

**Risk:** 14 out of 18 tests in `AppContextEngineTests` directly assert `context.textMode`. Deleting them reduces test coverage for `AppContextEngine`. Some tests (like override priority, unknown app fallback) test AppContextEngine logic that no longer exists -- these should be deleted. But bundleId/appName detection tests should be preserved.

**Mitigation:** Keep tests that verify `bundleId` and `appName` detection (remove textMode assertions from them). Delete tests that ONLY test TextMode mapping (override priority, fallback, per-app modes). Keep all SuperTextStyle prompt tests unchanged.

### 8.4 LOW: Analytics metadata gap

**Risk:** Removing `AnalyticsMetadataKey.textMode` from dictation_started metadata means historical comparison between old events (with text_mode) and new events (without) may show missing field.

**Mitigation:** The `effectiveStyle` key (line 863) already carries the style information via `SuperTextStyle.rawValue`. The `text_mode` key was vestigial since Phase 7 added `effective_style`. No data loss.

### 8.5 LOW: Documentation drift

**Risk:** `docs/architecture.md`, `benchmarks/README.md`, and `CLAUDE.md` still reference TextMode. These are documentation files, not compiled code.

**Mitigation:** Update `docs/architecture.md` file tree (line 73) to remove TextMode.swift. CLAUDE.md GSD sections will be updated when STATE.md is updated. Low priority.

### 8.6 LOW: HistoryItem.textMode field

**Risk:** Old database entries have TextMode values ("chat", "email", etc.) in the `textMode` String column. `SuperTextStyle(rawValue: "chat")` returns nil, so old entries show no style badge.

**Mitigation:** This is by design (D-05). No SwiftData migration needed (D-07). New entries write `SuperTextStyle.rawValue` or "none".

---

*Research complete: 2026-04-02*
*Phase: 09-textmode-deletion*
*Files read: 24 production + test files, full codebase grep for 10 symbol patterns*
