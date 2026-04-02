# Milestones

## v1.0 Стили текста v2 (Shipped: 2026-04-02)

**Phases completed:** 9 phases, 13 plans, 22 tasks

**Key accomplishments:**

- Extracted SnippetPlaceholder, SnippetContext, NormalizationHints into separate Models/ files, removed textMode field from NormalizationHints
- All 7 test files migrated from TextMode to SuperTextStyle pipeline signatures -- 1047 tests, 0 failures
- Style-aware NormalizationGate with bidirectional alias lookup, style-neutral edit distance, and relaxed thresholds for SuperTextStyle-driven normalization
- superStyle parameter threaded through NormalizationPipeline.postflight() and both PipelineEngine gate call sites, connecting style-aware gate to production pipeline
- cardDescription на SuperTextStyle (3 стиля), displayName на SuperStyleMode, и SettingsSection.textStyle с sidebar metadata
- TextStyleSettingsContent SwiftUI view with segmented Авто/Ручной picker, 3 style cards, and context-aware model-missing overlay wired into SettingsView
- TextMode enum, AppModeSettingsView, NSWorkspaceProvider file, and all TextMode references removed from production code -- AppContext now carries only bundleId and appName

---
