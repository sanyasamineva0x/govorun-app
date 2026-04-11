# Design System v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the entire visual identity — palette, typography, surfaces, components — as defined in `docs/superpowers/specs/2026-04-10-design-system-v2-design.md`.

**Architecture:** Visual-only changes in Views/ and App/ layers. Two color definition sites: SwiftUI (`SettingsTheme.swift`) and AppKit (`BottomBarWindow.swift`). Font bundled via XcodeGen copy phase. No Core/Services changes.

**Tech Stack:** SwiftUI, AppKit (NSColor), XcodeGen, Source Serif 4 variable font

**Spec:** `docs/superpowers/specs/2026-04-10-design-system-v2-design.md`

---

### Task 1: Bundle Source Serif 4 font

**Files:**
- Create: `Govorun/Fonts/SourceSerif4-Variable.ttf`
- Modify: `project.yml:58-73` (copy phases)
- Modify: `Govorun/Info.plist`

- [ ] **Step 1: Download Source Serif 4 variable font**

```bash
mkdir -p Govorun/Fonts
curl -L "https://github.com/adobe-fonts/source-serif/raw/release/TTF/SourceSerif4Variable-Roman.ttf" \
  -o Govorun/Fonts/SourceSerif4-Variable.ttf
```

- [ ] **Step 2: Add font copy phase to project.yml**

In `project.yml`, add a new copy phase after the existing `copyFiles` entries. Find the `copyFiles:` array (line 58) and append:

```yaml
  - destination: resources
    subpath: Fonts
    buildPhase: resourcesBuildPhase
    files:
      - path: Govorun/Fonts/SourceSerif4-Variable.ttf
```

- [ ] **Step 3: Register font in Info.plist**

Add the `ATSApplicationFontsPath` key to `Govorun/Info.plist` before the closing `</dict>`:

```xml
	<key>ATSApplicationFontsPath</key>
	<string>Fonts</string>
```

- [ ] **Step 4: Regenerate Xcode project and verify build**

```bash
xcodegen generate
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Govorun/Fonts/SourceSerif4-Variable.ttf project.yml Govorun/Info.plist
git commit -m "feat: добавить Source Serif 4 в bundle"
```

---

### Task 2: Replace palette and typography in SettingsTheme.swift

**Files:**
- Modify: `Govorun/Views/SettingsTheme.swift`

This is the core task — replaces all 5 colors, adds font helpers, and rewrites every component.

- [ ] **Step 1: Replace color definitions (lines 5-16)**

Replace the entire `Color` extension:

```swift
// MARK: - Фирменные цвета v2

extension Color {
    /// Snow #FEFEFE — основной фон
    static let snow = Color(red: 254/255, green: 254/255, blue: 254/255)
    /// Mist #F0EEEC — разделители, бордеры
    static let mist = Color(red: 240/255, green: 238/255, blue: 236/255)
    /// Ink #1B1917 — текст, кнопки
    static let ink = Color(red: 27/255, green: 25/255, blue: 23/255)
    /// Sage #3D7B6E — waveform, статус
    static let sage = Color(red: 61/255, green: 123/255, blue: 110/255)
    /// Ember #C85046 — ошибки
    static let ember = Color(red: 200/255, green: 80/255, blue: 70/255)
}
```

- [ ] **Step 2: Add font helper**

Add below the color extension:

```swift
// MARK: - Типографика

extension Font {
    /// Source Serif 4 — заголовки
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch weight {
        case .semibold:
            return .custom("SourceSerif4Variable-Roman", size: size)
                .weight(.semibold)
        default:
            return .custom("SourceSerif4Variable-Roman", size: size)
                .weight(.bold)
        }
    }
}
```

- [ ] **Step 3: Rewrite SectionPageHeader**

Replace the entire `SectionPageHeader` struct (lines 67-99):

```swift
struct SectionPageHeader: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.sage.opacity(0.7))

                Text(section.title)
                    .font(.serif(22))
                    .tracking(-0.4)
            }

            Text(section.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.ink.opacity(0.38))

            Rectangle()
                .fill(Color.mist)
                .frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }
}
```

- [ ] **Step 4: Rewrite SettingsCardModifier**

Replace `SettingsCardModifier` (lines 103-121):

```swift
struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(24)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.mist, lineWidth: 1)
            )
    }
}
```

- [ ] **Step 5: Rewrite StatusCardModifier → StatusDot**

Replace `StatusCardModifier` (lines 126-154) with an inline dot component:

```swift
struct StatusDot: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.sage : Color.mist)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ink.opacity(0.5))
        }
    }
}
```

Remove the `statusCard(accent:)` View extension.

- [ ] **Step 6: Rewrite BrandedEmptyState**

Replace `BrandedEmptyState` (lines 178-218):

```swift
struct BrandedEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 24)

            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Color.ink.opacity(0.12))

            Text(title)
                .font(.serif(17, weight: .semibold))
                .tracking(-0.2)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ink.opacity(0.38))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 7: Rewrite BrandedButton**

Replace `BrandedButton` (lines 222-244):

```swift
struct BrandedButton: View {
    let title: String
    let style: Style
    let action: () -> Void

    enum Style {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(style == .primary ? .white : Color.ink.opacity(0.5))
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(style == .primary ? Color.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style == .primary ? Color.clear : Color.mist, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 8: Rewrite SettingsSearchBar**

Replace `SettingsSearchBar` (lines 248-274):

```swift
struct SettingsSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Поиск…"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(Color.ink.opacity(0.25))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ink.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mist)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 9: Rewrite CountBadge**

Replace `CountBadge` (lines 302-314):

```swift
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.ink.opacity(0.38))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.mist)
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 10: Rewrite AddButton**

Replace `AddButton` (lines 318-340):

```swift
struct AddButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.ink.opacity(isHovered ? 0.8 : 0.5))
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
```

- [ ] **Step 11: Rewrite SettingsToggleRow**

Replace `SettingsToggleRow` (lines 344-373):

```swift
struct SettingsToggleRow: View {
    let title: String
    let description: String
    let icon: String
    var iconColor: Color = .sage
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor.opacity(0.7))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.ink.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.ink)
        }
    }
}
```

- [ ] **Step 12: Run tests**

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20
```

Expected: all tests pass (no color references in tests — these are UI-only changes)

- [ ] **Step 13: Commit**

```bash
git add Govorun/Views/SettingsTheme.swift
git commit -m "feat: дизайн-система v2 — палитра, типографика, компоненты"
```

---

### Task 3: Replace BrandColors in BottomBarWindow.swift

**Files:**
- Modify: `Govorun/App/BottomBarWindow.swift:24-34`

- [ ] **Step 1: Replace BrandColors enum**

Replace lines 24-34 (the `BrandColors` enum):

```swift
enum BrandColors {
    /// Sage #3D7B6E — waveform, processing
    static let sage = NSColor(red: 61/255, green: 123/255, blue: 110/255, alpha: 1)
    /// Ember #C85046 — ошибки
    static let ember = NSColor(red: 200/255, green: 80/255, blue: 70/255, alpha: 1)
    /// Ink #1B1917 — текст
    static let ink = NSColor(red: 27/255, green: 25/255, blue: 23/255, alpha: 1)

    // Обратная совместимость — старые имена → новые цвета
    static let cottonCandy = sage
    static let skyAqua = sage
    static let oceanMist = sage
    static let petalFrost = NSColor.clear
    static let alabasterGrey = NSColor(red: 240/255, green: 238/255, blue: 236/255, alpha: 1)
}
```

Compatibility aliases ensure `BottomBarView.swift` compiles before we update it in the next task.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Govorun/App/BottomBarWindow.swift
git commit -m "feat: BrandColors v2 — Sage, Ember, Ink"
```

---

### Task 4: Update BottomBarView.swift

**Files:**
- Modify: `Govorun/App/BottomBarView.swift`

- [ ] **Step 1: Update stateTint (lines 160-177)**

Replace the `stateTint` computed property:

```swift
    @ViewBuilder
    private var stateTint: some View {
        switch controller.state {
        case .hidden:
            Color.clear
        case .recording:
            Color(nsColor: BrandColors.sage).opacity(0.12)
        case .processing:
            Color(nsColor: BrandColors.sage).opacity(0.07)
        case .modelLoading, .modelDownloading:
            Color(nsColor: BrandColors.sage).opacity(0.07)
        case .accessibilityHint:
            Color(nsColor: BrandColors.sage).opacity(0.08)
        case .error:
            Color(nsColor: BrandColors.ember).opacity(0.12)
        }
    }
```

- [ ] **Step 2: Update WaveformBar (lines 216-253)**

In `WaveformBar`, replace `BrandColors.cottonCandy` with `BrandColors.sage`:

```swift
    var body: some View {
        RoundedRectangle(cornerRadius: BottomBarMetrics.barWidth/2)
            .fill(Color(nsColor: BrandColors.sage))
            .frame(width: BottomBarMetrics.barWidth, height: barHeight)
            .shadow(
                color: Color(nsColor: BrandColors.sage)
                    .opacity(glowOpacity),
                radius: glowRadius
            )
            .animation(PillMotion.barSpring, value: audioLevel)
    }
```

Update glow constants — in `PillMotion` (line 30):

```swift
    static let glowOpacityScale: Double = 0.3
    static let glowRadiusScale: CGFloat = 5.0
```

(`glowRadiusScale` from 2.5 → 5.0 per spec)

- [ ] **Step 3: Update ProcessingView (lines 257-298)**

Replace `BrandColors.skyAqua` with `BrandColors.sage`:

```swift
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: BrandColors.sage))
                    .frame(width: 2.5, height: barHeight(for: index))
                    .opacity(barOpacity(for: index))
                    .shadow(
                        color: Color(nsColor: BrandColors.sage)
                            .opacity(index == activeIndex ? 0.3 : 0),
                        radius: 2
                    )
                    .animation(PillMotion.pulseCurve, value: activeIndex)
```

- [ ] **Step 4: Update ModelLoadingView (lines 320-333)**

Replace `BrandColors.skyAqua` with `BrandColors.sage`:

```swift
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(nsColor: BrandColors.sage))
```

- [ ] **Step 5: Update ModelDownloadingView (lines 337-352)**

Same replacement — `skyAqua` → `sage`:

```swift
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(nsColor: BrandColors.sage))
```

- [ ] **Step 6: Update AccessibilityHintView (lines 356-369)**

Replace `BrandColors.oceanMist` with `BrandColors.sage`:

```swift
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color(nsColor: BrandColors.sage))
                .font(.system(size: 12, weight: .medium))
```

- [ ] **Step 7: Update ErrorView (lines 373-389)**

Replace `BrandColors.cottonCandy` with `BrandColors.ember`:

```swift
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: BrandColors.ember))
                .font(.system(size: 12, weight: .medium))
```

- [ ] **Step 8: Remove compatibility aliases from BottomBarWindow.swift**

Now that all references are updated, remove the aliases added in Task 3:

```swift
enum BrandColors {
    static let sage = NSColor(red: 61/255, green: 123/255, blue: 110/255, alpha: 1)
    static let ember = NSColor(red: 200/255, green: 80/255, blue: 70/255, alpha: 1)
    static let ink = NSColor(red: 27/255, green: 25/255, blue: 23/255, alpha: 1)
    static let mist = NSColor(red: 240/255, green: 238/255, blue: 236/255, alpha: 1)
}
```

- [ ] **Step 9: Build and test**

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED, all tests pass

- [ ] **Step 10: Commit**

```bash
git add Govorun/App/BottomBarView.swift Govorun/App/BottomBarWindow.swift
git commit -m "feat: BottomBar v2 — Sage waveform, Ember errors"
```

---

### Task 5: Update SettingsView.swift

**Files:**
- Modify: `Govorun/Views/SettingsView.swift`

This is the biggest view file — sidebar, general settings, product mode card are all here.

- [ ] **Step 1: Replace all color references**

Global replacements in `SettingsView.swift`:

| Find | Replace |
|------|---------|
| `Color.cottonCandy` | `Color.sage` |
| `Color.skyAqua` | `Color.sage` |
| `Color.oceanMist` | `Color.sage` |
| `Color.alabasterGrey` | `Color.mist` |

- [ ] **Step 2: Update sidebar selected state (around line 126)**

Replace the selected background/accent:

```swift
// Selected background: was cottonCandy.opacity(0.14)
.background(Color.ink.opacity(0.06))

// Accent bar: was cottonCandy
.fill(Color.ink)

// Selected icon: was cottonCandy
.foregroundStyle(Color.ink)
```

- [ ] **Step 3: Update section header fonts**

Find `.font(.system(size: 20, weight: .semibold))` (page title) and replace:

```swift
.font(.serif(22))
.tracking(-0.4)
```

Find `.font(.system(size: 28, weight: .bold))` (welcome heading, if present) and replace:

```swift
.font(.serif(28))
.tracking(-0.8)
```

- [ ] **Step 4: Replace .settingsCard() usages**

For sections that used `.settingsCard()`, wrap content in divider-based groups instead. Each `.settingsCard()` call becomes the new card modifier (which now uses Mist border + 14pt radius).

- [ ] **Step 5: Replace StatusCardModifier usages**

Replace any `.statusCard(accent:)` with inline `StatusDot`:

```swift
// Was: someContent.statusCard(accent: .oceanMist)
// Now:
StatusDot(title: "Super активен", isActive: true)
```

- [ ] **Step 6: Build to verify**

```bash
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Govorun/Views/SettingsView.swift
git commit -m "feat: SettingsView v2 — Ink sidebar, serif headers, Sage icons"
```

---

### Task 6: Update OnboardingView.swift

**Files:**
- Modify: `Govorun/Views/OnboardingView.swift`

- [ ] **Step 1: Replace all color references**

Global replacements:

| Find | Replace |
|------|---------|
| `Color.cottonCandy` | `Color.sage` |
| `Color.oceanMist` | `Color.sage` |
| `Color.alabasterGrey` | `Color.mist` |

- [ ] **Step 2: Update progress bar gradient (lines 55-60)**

Replace the progress bar fill:

```swift
LinearGradient(
    colors: [Color.sage, Color.sage.opacity(0.6)],
    startPoint: .leading,
    endPoint: .trailing
)
```

Background track:

```swift
Color.mist
```

- [ ] **Step 3: Update step title fonts**

Replace all `.font(.system(size: 22, weight: .bold))` in step titles:

```swift
.font(.serif(22))
.tracking(-0.4)
```

Replace `.font(.system(size: 28, weight: .bold))` in welcome title:

```swift
.font(.serif(28))
.tracking(-0.8)
```

- [ ] **Step 4: Replace .settingsCard() usages**

Replace `.settingsCard()` with the updated modifier.

- [ ] **Step 5: Build to verify**

```bash
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Govorun/Views/OnboardingView.swift
git commit -m "feat: OnboardingView v2 — Sage progress, serif titles"
```

---

### Task 7: Update DictionaryView, SnippetListView, HistoryView

**Files:**
- Modify: `Govorun/Views/DictionaryView.swift`
- Modify: `Govorun/Views/SnippetListView.swift`
- Modify: `Govorun/Views/HistoryView.swift`

- [ ] **Step 1: Update DictionaryView.swift**

Replace color references:

```swift
// Line 79: was Color.skyAqua.opacity(0.5)
Color.sage.opacity(0.5)
```

- [ ] **Step 2: Update SnippetListView.swift**

Replace color references:

```swift
// Line 85: was Color.skyAqua (fuzzy badge text)
Color.sage

// Line 89: was Color.skyAqua (fuzzy badge bg)
Color.sage

// Line 112: was Color.oceanMist (enabled checkmark)
Color.sage
```

- [ ] **Step 3: Update HistoryView.swift**

Replace color references:

```swift
// Line 35: was Color.cottonCandy (clear button text)
Color.ink.opacity(0.5)

// Line 38: was Color.cottonCandy.opacity(0.15) (clear button bg)
Color.mist

// Line 90: was Color.oceanMist / Color.cottonCandy (audio icons)
Color.sage // playing
Color.ink.opacity(0.38) // paused

// Line 129: was Color.cottonCandy.opacity(isHovered ? 0.06 : 0) (hover)
Color.ink.opacity(isHovered ? 0.04 : 0)
```

Replace `.settingsCard()` on line 48 with the updated modifier.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Govorun/Views/DictionaryView.swift Govorun/Views/SnippetListView.swift Govorun/Views/HistoryView.swift
git commit -m "feat: Dictionary/Snippet/History v2 — Sage accents, Ink hover"
```

---

### Task 8: Update TextStyleSettingsView.swift

**Files:**
- Modify: `Govorun/Views/TextStyleSettingsView.swift`

- [ ] **Step 1: Replace color references**

```swift
// Line 99: was Color.cottonCandy (checkmark)
Color.sage

// Line 166: was .ultraThinMaterial.opacity(0.8) (overlay)
Color.snow.opacity(0.85)
```

- [ ] **Step 2: Replace .settingsCard() usages**

Lines 33, 44, 103 — replace with the updated modifier.

- [ ] **Step 3: Update section title font**

Line 78: was `.font(.system(size: 22, weight: .bold))`:

```swift
.font(.serif(22))
.tracking(-0.4)
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Govorun/Views/TextStyleSettingsView.swift
git commit -m "feat: TextStyleSettings v2 — Sage checkmarks, serif titles"
```

---

### Task 9: Remove old color names from SwiftUI

**Files:**
- Modify: `Govorun/Views/SettingsTheme.swift`

- [ ] **Step 1: Verify no remaining references to old colors**

```bash
cd /Users/sanyasamineva/Desktop/govorun-app
grep -rn 'cottonCandy\|skyAqua\|oceanMist\|petalFrost\|alabasterGrey' Govorun/Views/ Govorun/App/ --include='*.swift'
```

Expected: only `SettingsTheme.swift` color definitions remain (lines 5-16 of old code, already replaced in Task 2). If any other files still reference old names, fix them.

- [ ] **Step 2: Run full test suite**

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -30
```

Expected: all tests pass. No test references old color names (colors are not tested in unit tests).

- [ ] **Step 3: Grep tests for old references**

```bash
grep -rn 'cottonCandy\|skyAqua\|oceanMist\|petalFrost\|alabasterGrey' GovorunTests/ --include='*.swift'
```

If any test files reference old colors (e.g., in mock setups), update them to the new names.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: убрать старые имена цветов"
```

---

### Task 10: Build DMG and visual smoke test

**Files:**
- None (verification only)

- [ ] **Step 1: Build DMG**

```bash
pkill -f Govorun 2>/dev/null; sleep 1
bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)'
```

Expected: DMG built successfully

- [ ] **Step 2: Install and launch**

```bash
rm -rf /Applications/Govorun.app
hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null
MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}')
cp -R "$MOUNT/Govorun.app" /Applications/
hdiutil detach "$MOUNT" 2>/dev/null
xattr -cr /Applications/Govorun.app
open /Applications/Govorun.app
```

- [ ] **Step 3: Visual checklist**

Verify manually:
- [ ] Settings window opens — serif headers visible (Source Serif 4 bold)
- [ ] Sidebar icons are Sage green, not Cotton Candy
- [ ] Toggle switches: on = dark (#1B1917), off = light gray (#F0EEEC)
- [ ] Buttons are dark, not colored
- [ ] Cards have thin Mist borders, no material/blur
- [ ] Recording pill shows Sage green waveform
- [ ] Processing shows Sage pulse
- [ ] Empty states have dark buttons, serif titles, faint icons

- [ ] **Step 4: Final commit (if any visual tweaks needed)**

```bash
git add -A
git commit -m "fix: визуальные правки после smoke test"
```
