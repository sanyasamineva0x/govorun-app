---
phase: 09-textmode-deletion
plan: 02
subsystem: tests
tags: [swift, textmode, tests, deletion, cleanup]

requires:
  - phase: 09-textmode-deletion plan 01
    provides: Production code TextMode deletion complete
provides:
  - Zero TextMode references in GovorunTests/
  - All test files compile and pass against simplified AppContext and AppContextEngine
affects: []

tech-stack:
  added: []
  patterns: []

key-files:
  - GovorunTests/AppContextEngineTests.swift
  - GovorunTests/HistoryStoreTests.swift
  - GovorunTests/IntegrationTests.swift

duration: ~5min
tasks_completed: 4
files_modified: 3
tests_before: 1075
tests_after: 1061
---

# Summary: Plan 09-02 -- Test cleanup: remove TextMode from all test files

## What changed

### AppContextEngineTests.swift (full rewrite)
- Deleted `MockAppModeOverrides` class (was 15 lines, referenced deleted `AppModeOverriding` protocol)
- Deleted 14 tests that asserted `context.textMode` (tests 1-6, 11-18 in original numbering)
- Simplified `makeEngine()` helper: removed `overrides` parameter, returns 2-tuple instead of 3-tuple
- Added 4 new tests for bundleId/appName detection (Telegram, Safari, unknown app, nil)
- Kept 7 SuperTextStyle prompt tests unchanged (already migrated in earlier phases)
- Net test count: 18 old -> 11 new

### HistoryStoreTests.swift (2 edits)
- `makeAppContext()` helper: `AppContext(bundleId:appName:textMode:)` -> `AppContext(bundleId:appName:)`
- Inline `AppContext` in `test_save_countsWordsWithNewlines`: removed `textMode: .universal` argument
- Kept `item.textMode` String assertion (line 68) -- this reads the HistoryItem String property, not the deleted enum

### IntegrationTests.swift (1 edit)
- `AppContextEngine(workspace:modeOverrides:)` -> `AppContextEngine(workspace:)` in `makeTestAppState()`
- Removed `MockAppModeOverrides()` instantiation

## Verification

- `grep -rn "TextMode" --include="*.swift" GovorunTests/` returns 0 results
- `grep -rn "AppModeOverriding" --include="*.swift" GovorunTests/` returns 0 results
- `grep -rn "MockAppModeOverrides" --include="*.swift" GovorunTests/` returns 0 results
- `xcodebuild test` -- 1061 tests, 0 failures -- **TEST SUCCEEDED**
- Allowed residuals: `item.textMode` (String property on HistoryItem) in HistoryStoreTests, HistoryItem.swift, HistoryStore.swift, HistoryView.swift

## Decisions

- No SwiftData migration needed -- `HistoryItem.textMode` remains a String column storing style name
- 14 TextMode-specific tests removed without replacement -- the TextMode enum and its mapping logic are gone from production code, so no behavior to test
