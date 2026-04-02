# Phase 8: UI — Research

**Date:** 2026-04-01
**Focus:** SwiftUI settings tab for SuperTextStyle switching (auto/manual)

---

## 1. Existing UI Patterns

### SettingsView Architecture (`Govorun/Views/SettingsView.swift`)

The settings window uses a sidebar + content pattern:

- `SettingsView` — top-level: `HStack` with `SettingsSidebar` (200px) + `Divider` + `ScrollView` content
- `@State private var selectedSection: SettingsSection = .general` drives navigation
- Content is rendered via a `switch selectedSection` block (lines 18-29)
- Each section is a separate View (e.g. `GeneralSettingsContent`, `AppModeSettingsView`, `DictionaryView`)
- Content area has `padding(24)`, `id(selectedSection)`, opacity+offset transition on section change
- `appState` is passed via `@EnvironmentObject` (not explicit parameter)

### SettingsSection Enum (`Govorun/Views/SettingsTheme.swift`, lines 20-63)

```swift
enum SettingsSection: String, Identifiable {
    case general
    case appModes   // hidden until Phase 5
    case dictionary
    case snippets
    case history

    static let visibleCases: [SettingsSection] = [.general, .dictionary, .snippets, .history]
    // Each case has: title, subtitle, icon
}
```

**To add "Стиль текста" section:**
1. Add `case textStyle` to enum
2. Update `visibleCases` — insert at position 1 (after general, before dictionary)
3. Add `title` return: `"Стиль текста"`
4. Add `subtitle` return: e.g. `"Настройка стиля текста для Супер-режима"`
5. Add `icon` return: e.g. `"textformat"` or `"paintbrush"` or `"text.badge.checkmark"`
6. Add case to `switch selectedSection` in `SettingsView.body`

### GeneralSettingsContent — Data Binding Pattern (lines 172-180)

```swift
private struct GeneralSettingsContent: View {
    @EnvironmentObject private var appState: AppState

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { appState.settings[keyPath: keyPath] = $0 }
        )
    }
    // Usage: settingsBinding(\.productMode), settingsBinding(\.recordingMode), etc.
}
```

The new TextStyleSettingsContent will use the same pattern for `settingsBinding(\.superStyleMode)` and `settingsBinding(\.manualSuperStyle)`.

### ProductModeCard — Reference Pattern (lines 287-565)

This is the closest existing pattern for what Phase 8 needs. Key elements:

- Takes `@Binding var selection: ProductMode` + `@EnvironmentObject appState`
- Uses `SectionHeader` for title
- `.segmented` Picker for mode switching
- Dependent content below the picker changes based on selection
- Checks `appState.superAssetsState` for model availability
- Uses `.settingsCard()` modifier for visual container
- Complex download status view with multiple states

**Key difference from Phase 8:** ProductModeCard shows download UI inline. Phase 8 needs disabled overlay on the entire card content when model is missing.

---

## 2. Data Layer (Phase 6 — Complete)

### SettingsStore (`Govorun/Storage/SettingsStore.swift`)

Already has both properties:

```swift
var superStyleMode: SuperStyleMode {
    get { ... }  // default .auto
    set { ... objectWillChange.send() }
}

var manualSuperStyle: SuperTextStyle {
    get { ... }  // default .normal
    set { ... objectWillChange.send() }
}
```

Both registered in `registerDefaults()` and cleared in `resetToDefaults()`. Ready to use with `settingsBinding(\.superStyleMode)` and `settingsBinding(\.manualSuperStyle)`.

### SuperStyleMode Enum (`Govorun/Models/SuperTextStyle.swift`)

```swift
enum SuperStyleMode: String, CaseIterable {
    case auto
    case manual
}
```

Needs `displayName` computed property for Picker labels:
- `.auto` -> "Авто"
- `.manual` -> "Ручной"

**Note:** `SuperStyleMode` does not conform to `Identifiable` — need `id: \.self` in ForEach or add conformance.

---

## 3. SuperTextStyle Model Properties

### Available Properties (`Govorun/Models/SuperTextStyle.swift`)

```swift
enum SuperTextStyle: String, CaseIterable, Codable {
    case relaxed    // displayName: "Расслабленный"
    case normal     // displayName: "Обычный"
    case formal     // displayName: "Формальный"
}
```

Existing computed properties:
- `displayName: String` — Russian display name (already exists)
- `styleBlock: String` — full style description (too long for card UI)
- `terminalPeriod: Bool` — determines trailing period
- `contract: LLMOutputContract` — normalization contract
- `applyDeterministic(_:)` — caps transformation

**For card descriptions, need short descriptions.** Options:
1. Add `var cardDescription: String` computed property to `SuperTextStyle`
2. Hardcode descriptions directly in the View

Recommended: Add `cardDescription` to `SuperTextStyle` (keeps model as single source of truth). Example descriptions:
- relaxed: "Как в мессенджере — строчные буквы, бренды кириллицей, без точки"
- normal: "Стандартный — заглавная буква, бренды оригинальные, без точки"
- formal: "Деловой — заглавная буква, бренды оригинальные, сленг раскрыт, точка в конце"

---

## 4. Model Availability Check

### AppState.superAssetsState (`Govorun/App/AppState.swift`)

```swift
@Published private(set) var superAssetsState: SuperAssetsState = .unknown
```

### SuperAssetsState Enum (`Govorun/Services/SuperAssetsManager.swift`)

```swift
enum SuperAssetsState: Equatable {
    case unknown
    case checking
    case installed
    case modelMissing
    case runtimeMissing
    case error(String)
}
```

**Model available** = `superAssetsState == .installed`

**Model NOT available** = any other state. For Phase 8 overlay, key states:
- `.modelMissing` — show overlay with download button
- `.runtimeMissing` — show overlay with "llama-server отсутствует"
- `.unknown`, `.checking` — show loading state or disabled
- `.error(msg)` — show error with retry

**Existing pattern from ProductModeCard:** switch on `appState.superAssetsState` with per-case handling.

**Also relevant:** `appState.settings.productMode != .superMode` — if user is in Standard mode, style settings could be shown but noted as "requires Super mode".

### Download Navigation

D-04 says overlay should have a button to navigate to download. Two options:
1. Programmatically switch to General tab and scroll to ProductModeCard
2. Trigger `appState.startSuperModelDownload()` directly from overlay

Option 2 is simpler and already used in ProductModeCard. But D-04 says "кнопка перехода к скачиванию" — navigating to the General tab where download already exists is cleaner. Can set `selectedSection = .general` via a Binding or callback.

---

## 5. Disabled/Overlay Pattern

### SwiftUI Approach for D-04

The decision (D-04) requires: cards visible but disabled (grey/blurred), overlay with explanation + download button.

Implementation approach:

```swift
ZStack {
    // Content (style cards)
    VStack { ... }
        .opacity(modelAvailable ? 1.0 : 0.4)
        .blur(radius: modelAvailable ? 0 : 1)
        .disabled(!modelAvailable)
        .allowsHitTesting(modelAvailable)

    // Overlay
    if !modelAvailable {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Для стилей нужна ИИ-модель")
                .font(.callout.weight(.medium))
            Text("Скачайте модель в разделе «Основные»")
                .font(.caption)
                .foregroundStyle(.secondary)
            BrandedButton(title: "Перейти к скачиванию", style: .primary) {
                // navigate to general tab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

**Key consideration:** The overlay needs to cover only the style cards area, not the auto/manual segment. The segment should work regardless of model availability (per D-02: "Вкладка всегда видна в сайдбаре").

Actually, re-reading D-02: "Без модели — disabled контент с overlay поверх карточек." The segment picker itself could still function (user picks auto/manual), but the content below (auto status text or manual cards) is disabled with overlay.

---

## 6. View Structure Recommendation

### Option A: Single File
`TextStyleSettingsContent` in a new file `Govorun/Views/TextStyleSettingsView.swift`

### Option B: Split Files
- `TextStyleSettingsView.swift` — main content view
- Add to `SettingsTheme.swift` — if new reusable components emerge

**Recommendation:** Single file (Option A). The view is self-contained. Extract sub-views as private structs within the file (same pattern as ProductModeCard is private in SettingsView.swift).

### Proposed View Hierarchy

```
TextStyleSettingsContent (main)
├── SectionHeader ("Режим стиля", icon: "textformat")
├── Segmented Picker (Авто / Ручной)  [always enabled]
├── ZStack  [overlay zone]
│   ├── Content (depends on mode):
│   │   ├── Auto: Static text "Стиль определяется автоматически по приложению"
│   │   └── Manual: VStack of 3 StyleCards
│   │       ├── StyleCard(.relaxed)
│   │       ├── StyleCard(.normal)
│   │       └── StyleCard(.formal)
│   └── ModelMissingOverlay (conditional)
```

### StyleCard Design

Full-width vertical card with:
- Left: style icon or accent color bar
- Title: `style.displayName` ("Расслабленный")
- Description: short description of what the style does
- Right: checkmark if selected (`Image(systemName: "checkmark.circle.fill")`)
- Tap handler: sets `manualSuperStyle = style`

Use `.settingsCard()` or lighter styling (just background + rounded corners) to avoid too much nesting since the whole section is already in a card.

---

## 7. Integration Points Summary

### Files to Modify

| File | Change |
|------|--------|
| `Govorun/Views/SettingsTheme.swift` | Add `case textStyle` to `SettingsSection`, update `visibleCases`, add title/subtitle/icon |
| `Govorun/Views/SettingsView.swift` | Add `case .textStyle: TextStyleSettingsContent()` to switch |
| `Govorun/Models/SuperTextStyle.swift` | Add `cardDescription` computed property |

### Files to Create

| File | Content |
|------|---------|
| `Govorun/Views/TextStyleSettingsView.swift` | `TextStyleSettingsContent`, `StyleCard`, overlay logic |

### Files NOT to Modify

- `SettingsStore.swift` — already has `superStyleMode` and `manualSuperStyle` (Phase 6)
- `AppState.swift` — already has `superAssetsState` (existing)
- `AppModeSettingsView.swift` — will be deleted in Phase 9, not modified here

---

## 8. Edge Cases and Considerations

### SuperStyleMode Display Names
`SuperStyleMode` needs `title` or `displayName` for the segmented picker. Currently has no display properties. Add either:
- Property on `SuperStyleMode` itself (cleaner)
- Inline strings in the View

### Section Visibility
D-02 says "Вкладка всегда видна в сайдбаре." This means `textStyle` goes into `visibleCases` unconditionally — no gating on `productMode` or `superAssetsState`.

### No productMode Gating
The original spec says "на странице Говорун Супер" but D-01 overrides this — it's a standalone sidebar section, visible regardless of productMode. The overlay handles the "no model" case.

However, consider: should the tab be visible when productMode is `.standard`? The CONTEXT.md says "always visible in sidebar" and "without model — disabled content with overlay". Standard mode users might not have Super enabled at all. The safest interpretation: always show the tab, but show a different overlay for standard mode vs super-without-model.

**Recommendation:** Show overlay when `appState.superAssetsState != .installed` (covers both standard-mode and super-without-model). The overlay text can be context-aware.

### Animations
- Mode switch (auto/manual): `.animation(.easeInOut)` on the content transition
- Card selection: brief scale or highlight animation
- Overlay appear/disappear: fade transition

### StaggeredAppear
Follow existing pattern — apply `.staggeredAppear(index:)` to major content blocks within the section.

---

## 9. Spec vs CONTEXT.md Discrepancies

| Topic | Spec Says | CONTEXT.md Says | Use |
|-------|-----------|-----------------|-----|
| Location | "Вкладка в menubar-меню" | D-01: "Новая секция в SettingsView" | CONTEXT.md |
| No-model behavior | "NSAlert с предложением скачать" | D-04: "Overlay с пояснением и кнопкой" | CONTEXT.md |
| Auto mode display | "текущий стиль серым (Расслабленный · Telegram)" | D-05: "Static text, no live update" | CONTEXT.md |
| Cards layout | "три карточки" (no detail) | D-03: "Vertical, full width, description" | CONTEXT.md |

All CONTEXT.md decisions override spec. The requirements in REQUIREMENTS.md (UI-01 through UI-04) use spec wording but implementation follows CONTEXT.md decisions.

---

## 10. Requirement Mapping

| Req | Description | Implementation |
|-----|-------------|----------------|
| UI-01 | Tab "Стиль текста" present | New `SettingsSection.textStyle` + `TextStyleSettingsContent` view |
| UI-02 | Auto/Manual segment; auto shows style gray | Segmented Picker for `SuperStyleMode`; auto mode shows static description text |
| UI-03 | Manual: three style cards with descriptions, checkmark | Three `StyleCard` views, full width, checkmark on `manualSuperStyle` match |
| UI-04 | Without model: active but gray, download prompt | Disabled overlay with download navigation button (not NSAlert per D-04) |

---

## 11. Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, Xcode 15.4) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UI-01 | SettingsSection.textStyle exists in visibleCases, has correct title/subtitle/icon | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SettingsSectionTests` | ❌ Wave 0 |
| UI-02 | SuperStyleMode has displayName ("Авто"/"Ручной"); settingsBinding works for superStyleMode | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests` | ✅ (extend) |
| UI-03 | SuperTextStyle.cardDescription returns correct Russian descriptions for all 3 styles | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests` | ✅ (extend) |
| UI-04 | Model availability check: overlay logic depends on superAssetsState != .installed | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SettingsSectionTests` | ❌ Wave 0 |

**Note on UI testing:** SwiftUI views themselves (TextStyleSettingsContent, StyleCard, ModelMissingOverlay) are not unit-tested in this project per CLAUDE.md convention (986 existing tests, all logic-level). The testable surface for Phase 8 is:
- **Model properties** (cardDescription, displayName) — unit testable
- **Enum changes** (SettingsSection.textStyle cases, visibleCases) — unit testable
- **View logic** (overlay condition based on superAssetsState) — testable through model/state tests, not view rendering

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests -only-testing:GovorunTests/SettingsSectionTests`
- **Per wave merge:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `GovorunTests/SettingsSectionTests.swift` — covers UI-01 (textStyle in visibleCases, title/subtitle/icon) and UI-04 (model state enum coverage)
- [ ] Extend `GovorunTests/SuperTextStyleTests.swift` — covers UI-02 (SuperStyleMode.displayName) and UI-03 (SuperTextStyle.cardDescription)

*(No framework install needed — XCTest is built-in)*

---

## RESEARCH COMPLETE
