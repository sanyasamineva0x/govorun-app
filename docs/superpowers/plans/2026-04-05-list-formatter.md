# ListFormatter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect explicit list markers in Russian speech transcription and format them as numbered or dashed lists.

**Architecture:** New `ListFormatter` enum in `Core/` — stateless, pure function. Called as the final pass after style in both `applyPostProcessing()` (PipelineEngine) and `postflight()` (NormalizationPipeline). All marker families require 2+ matches; numbered families have priority over dashed.

**Tech Stack:** Swift 5.10, XCTest, TDD

**Spec:** `docs/superpowers/specs/2026-04-05-list-formatter-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Govorun/Core/ListFormatter.swift` | Marker detection, list formatting, punctuation cleanup |
| Create | `GovorunTests/ListFormatterTests.swift` | Unit tests for ListFormatter |
| Modify | `Govorun/Core/PipelineEngine.swift:323-328` | Add ListFormatter call to `applyPostProcessing()` |
| Modify | `Govorun/Core/NormalizationPipeline.swift:651` | Add ListFormatter call to `postflight()` |
| Modify | `GovorunTests/NormalizationPipelineTests.swift` | Integration test: postflight applies ListFormatter |
| Modify | `GovorunTests/PipelineEngineTests.swift` | Integration test: trivial path formats, standalone snippet untouched |

---

### Task 1: ListFormatter — marker detection + basic numbered list

**Files:**
- Create: `GovorunTests/ListFormatterTests.swift`
- Create: `Govorun/Core/ListFormatter.swift`

- [ ] **Step 1: Write failing tests for ordinal markers**

```swift
@testable import Govorun
import XCTest

final class ListFormatterTests: XCTestCase {
    // MARK: - Порядковые маркеры (2+)

    func test_ordinal_two_items() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_ordinal_three_items() {
        let input = "первое молоко второе хлеб третье масло"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб\n3. Масло")
    }

    func test_ordinal_single_no_change() {
        let input = "первое впечатление хорошее"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "первое впечатление хорошее")
    }

    // MARK: - Наречия (2+)

    func test_adverb_two_items() {
        let input = "во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_adverb_single_no_change() {
        let input = "во-первых это неправда"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "во-первых это неправда")
    }

    // MARK: - Пункты (2+)

    func test_punkt_two_items() {
        let input = "пункт один задача пункт два баг"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Задача\n2. Баг")
    }

    // MARK: - Без маркеров

    func test_no_markers_unchanged() {
        let input = "просто обычный текст без маркеров"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "просто обычный текст без маркеров")
    }

    func test_empty_string() {
        XCTAssertEqual(ListFormatter.format(""), "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(ListFormatter|TEST.*FAIL|Compil.*error)'`
Expected: compilation errors — `ListFormatter` not found.

- [ ] **Step 3: Implement ListFormatter with marker detection and numbered output**

```swift
import Foundation

enum ListFormatter {
    // MARK: - Семьи маркеров

    private enum ListStyle {
        case numbered
        case dashed
    }

    private struct MarkerFamily {
        let markers: [String]
        let style: ListStyle
    }

    private static let numberedFamilies: [MarkerFamily] = [
        MarkerFamily(markers: [
            "первое", "второе", "третье", "четвёртое", "пятое",
            "шестое", "седьмое", "восьмое", "девятое", "десятое",
        ], style: .numbered),
        MarkerFamily(markers: [
            "во-первых", "во-вторых", "в-третьих", "в-четвёртых", "в-пятых",
        ], style: .numbered),
        MarkerFamily(markers: [
            "пункт один", "пункт два", "пункт три", "пункт четыре", "пункт пять",
            "пункт шесть", "пункт семь", "пункт восемь", "пункт девять", "пункт десять",
        ], style: .numbered),
    ]

    private static let dashedFamilies: [MarkerFamily] = [
        MarkerFamily(markers: [
            "кроме того", "помимо этого", "а также",
            "плюс", "также", "ещё", "далее",
        ], style: .dashed),
    ]

    private static let allFamilies: [MarkerFamily] = numberedFamilies + dashedFamilies

    // MARK: - Public API

    static func format(_ text: String, style: SuperTextStyle? = nil) -> String {
        guard !text.isEmpty else { return "" }

        let lowered = text.lowercased()

        guard let (family, positions) = detectFamily(in: lowered) else {
            return text
        }

        let items = extractItems(from: text, positions: positions)
        let capitalize = style != .relaxed

        return buildList(
            items: items,
            style: family.style,
            capitalize: capitalize
        )
    }

    // MARK: - Детекция

    private static func detectFamily(
        in lowered: String
    ) -> (family: MarkerFamily, positions: [(range: Range<String.Index>, marker: String)])? {
        var bestFamily: MarkerFamily?
        var bestPositions: [(range: Range<String.Index>, marker: String)] = []

        for family in allFamilies {
            let positions = findMarkerPositions(in: lowered, markers: family.markers)
            guard positions.count >= 2 else { continue }

            let isNumbered = family.style == .numbered
            let bestIsNumbered = bestFamily?.style == .numbered

            if bestFamily == nil
                || (isNumbered && !bestIsNumbered)
                || (isNumbered == bestIsNumbered && positions.count > bestPositions.count)
            {
                bestFamily = family
                bestPositions = positions
            }
        }

        guard let family = bestFamily else { return nil }
        return (family, bestPositions)
    }

    private static func findMarkerPositions(
        in lowered: String,
        markers: [String]
    ) -> [(range: Range<String.Index>, marker: String)] {
        var positions: [(range: Range<String.Index>, marker: String)] = []

        for marker in markers {
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: marker, range: searchStart..<lowered.endIndex) {
                let isWordStart = range.lowerBound == lowered.startIndex
                    || lowered[lowered.index(before: range.lowerBound)].isWhitespace
                let isWordEnd = range.upperBound == lowered.endIndex
                    || lowered[range.upperBound].isWhitespace
                    || lowered[range.upperBound].isPunctuation

                if isWordStart && isWordEnd {
                    positions.append((range, marker))
                }
                searchStart = range.upperBound
            }
        }

        positions.sort { $0.range.lowerBound < $1.range.lowerBound }
        return positions
    }

    // MARK: - Извлечение пунктов

    private static func extractItems(
        from text: String,
        positions: [(range: Range<String.Index>, marker: String)]
    ) -> (header: String?, items: [String]) {
        var items: [String] = []
        let header: String?

        let firstPos = positions[0]
        let beforeFirst = String(text[text.startIndex..<firstPos.range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        header = beforeFirst.isEmpty ? nil : beforeFirst

        for i in 0..<positions.count {
            let start = positions[i].range.upperBound
            let end = i + 1 < positions.count
                ? positions[i + 1].range.lowerBound
                : text.endIndex
            let raw = String(text[start..<end])
            let cleaned = cleanItem(raw)
            items.append(cleaned)
        }

        return (header, items)
    }

    private static func cleanItem(_ raw: String) -> String {
        var s = raw

        // strip ведущей пунктуации (запятые, тире, двоеточия)
        while let first = s.unicodeScalars.first(where: { !CharacterSet.whitespaces.contains($0) }) {
            let ch = Character(first)
            if ch == "," || ch == ":" || ch == "-" || ch == "–" || ch == "—" {
                s = String(s.drop(while: { $0.isWhitespace || $0 == ch }))
            } else {
                break
            }
        }

        s = s.trimmingCharacters(in: .whitespaces)

        // strip trailing пунктуации
        while let last = s.last, last == "." || last == "," || last == ";" {
            s = String(s.dropLast())
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Сборка списка

    private static func buildList(
        items: (header: String?, items: [String]),
        style: ListStyle,
        capitalize: Bool
    ) -> String {
        var lines: [String] = []

        if let header = items.header {
            lines.append(header)
        }

        for (i, item) in items.items.enumerated() {
            guard !item.isEmpty else { continue }
            let formatted = capitalize ? capitalizeFirst(item) : item
            switch style {
            case .numbered:
                lines.append("\(i + 1). \(formatted)")
            case .dashed:
                lines.append("– \(formatted)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(ListFormatter|Test.*Passed|Test.*Failed)'`
Expected: all ListFormatterTests pass.

- [ ] **Step 5: Commit**

```bash
git add Govorun/Core/ListFormatter.swift GovorunTests/ListFormatterTests.swift
git commit -m "feat: ListFormatter — детекция маркеров списков, базовые нумерованные и дефисные списки"
```

---

### Task 2: Dashed markers, style-aware capitalization, edge cases

**Files:**
- Modify: `GovorunTests/ListFormatterTests.swift`

- [ ] **Step 1: Write failing tests for dashed markers, relaxed style, and edge cases**

Add to `ListFormatterTests`:

```swift
    // MARK: - Дефисные маркеры (2+)

    func test_dashed_two_items() {
        let input = "плюс скорость плюс простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота")
    }

    func test_dashed_three_items() {
        let input = "плюс скорость плюс простота плюс цена"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота\n– Цена")
    }

    func test_dashed_single_no_change() {
        let input = "плюс этого подхода в скорости"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюс этого подхода в скорости")
    }

    func test_dashed_phrase_markers() {
        let input = "кроме того скорость а также простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "– Скорость\n– Простота")
    }

    // MARK: - Капитализация по стилю

    func test_relaxed_no_capitalization() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .relaxed)
        XCTAssertEqual(result, "1. молоко\n2. хлеб")
    }

    func test_normal_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .normal)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_formal_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: .formal)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_nil_style_capitalizes() {
        let input = "первое молоко второе хлеб"
        let result = ListFormatter.format(input, style: nil)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    // MARK: - Шапка

    func test_header_with_list() {
        let input = "нужно купить первое молоко второе хлеб третье масло"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "нужно купить\n1. Молоко\n2. Хлеб\n3. Масло")
    }

    func test_header_no_auto_colon() {
        let input = "плюсы этого подхода во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюсы этого подхода\n1. Скорость\n2. Простота")
    }

    func test_header_preserves_dictated_colon() {
        let input = "купить: первое молоко второе хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "купить:\n1. Молоко\n2. Хлеб")
    }

    func test_marker_at_start_no_header() {
        let input = "во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    // MARK: - Приоритет семей

    func test_numbered_beats_dashed() {
        let input = "ещё одна вещь во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "ещё одна вещь\n1. Скорость\n2. Простота")
    }

    func test_weak_family_does_not_block_strong() {
        let input = "плюс контекст во-первых скорость во-вторых простота"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "плюс контекст\n1. Скорость\n2. Простота")
    }
```

- [ ] **Step 2: Run tests to verify new tests pass** (they should already pass with current implementation)

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(ListFormatter|Test.*Passed|Test.*Failed)'`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add GovorunTests/ListFormatterTests.swift
git commit -m "test: дефисные маркеры, style-aware caps, шапка, приоритет семей"
```

---

### Task 3: Punctuation boundary cleanup

**Files:**
- Modify: `GovorunTests/ListFormatterTests.swift`
- Modify: `Govorun/Core/ListFormatter.swift` (if `cleanItem` needs adjustment)

- [ ] **Step 1: Write failing tests for punctuation cleanup**

Add to `ListFormatterTests`:

```swift
    // MARK: - Очистка пунктуации

    func test_comma_after_marker_stripped() {
        let input = "во-первых, скорость, во-вторых, простота."
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота")
    }

    func test_dash_after_marker_stripped() {
        let input = "первое — молоко второе — хлеб"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_period_stripped() {
        let input = "первое молоко. второе хлеб."
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_semicolon_stripped() {
        let input = "первое молоко; второе хлеб;"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_trailing_comma_stripped() {
        let input = "первое молоко, второе хлеб,"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Молоко\n2. Хлеб")
    }

    func test_mixed_punctuation_cleanup() {
        let input = "во-первых, скорость; во-вторых — простота. в-третьих, цена,"
        let result = ListFormatter.format(input)
        XCTAssertEqual(result, "1. Скорость\n2. Простота\n3. Цена")
    }
```

- [ ] **Step 2: Run tests — fix any failures in `cleanItem` if needed**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(ListFormatter|Test.*Passed|Test.*Failed)'`

If the `cleanItem` method doesn't properly strip leading dashes after markers (the `—` in `"первое — молоко"`), update it. The current implementation should handle this since it strips `,`, `:`, `-`, `–`, `—` from the item start. Verify and fix if needed.

- [ ] **Step 3: Commit**

```bash
git add GovorunTests/ListFormatterTests.swift Govorun/Core/ListFormatter.swift
git commit -m "test: очистка пунктуации вокруг маркеров списков"
```

---

### Task 4: Integrate into PipelineEngine

**Files:**
- Modify: `Govorun/Core/PipelineEngine.swift:323-328`
- Modify: `GovorunTests/PipelineEngineTests.swift`

- [ ] **Step 1: Write failing integration test — trivial path formats lists**

Add to `PipelineEngineTests`:

```swift
    func test_trivial_path_formats_list() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "первое молоко второе хлеб")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: MockLLMClient(),
            snippetEngine: MockSnippetEngine()
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "1. Молоко\n2. Хлеб")
    }
```

- [ ] **Step 2: Write failing test — standalone snippet NOT formatted**

Add to `PipelineEngineTests`:

```swift
    func test_standalone_snippet_not_formatted_as_list() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "мой список")

        let snippets = MockSnippetEngine()
        snippets.configureStandalone("мой список", content: "первое молоко второе хлеб")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: MockLLMClient(),
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(
            result.normalizedText,
            "первое молоко второе хлеб",
            "standalone snippet — verbatim, ListFormatter не должен трогать"
        )
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(test_trivial_path_formats_list|test_standalone_snippet_not_formatted)'`
Expected: `test_trivial_path_formats_list` fails (ListFormatter not wired), `test_standalone_snippet_not_formatted` passes (already verbatim).

- [ ] **Step 4: Wire ListFormatter into `applyPostProcessing()`**

In `Govorun/Core/PipelineEngine.swift`, modify `applyPostProcessing` (line 323-328):

```swift
        func applyPostProcessing(_ text: String) -> String {
            let periodText = effectiveTerminalPeriod
                ? text
                : DeterministicNormalizer.stripTrailingPeriods(text)
            let styledText = currentSuperStyle?.applyDeterministic(periodText) ?? periodText
            return ListFormatter.format(styledText, style: currentSuperStyle)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(test_trivial_path_formats_list|test_standalone_snippet_not_formatted|Test.*Passed|Test.*Failed)'`
Expected: both pass. Standalone snippet is unaffected because it doesn't go through `applyPostProcessing`.

- [ ] **Step 6: Commit**

```bash
git add Govorun/Core/PipelineEngine.swift GovorunTests/PipelineEngineTests.swift
git commit -m "feat: интегрировать ListFormatter в PipelineEngine.applyPostProcessing"
```

---

### Task 5: Integrate into NormalizationPipeline.postflight

**Files:**
- Modify: `Govorun/Core/NormalizationPipeline.swift:651`
- Modify: `GovorunTests/NormalizationPipelineTests.swift`

- [ ] **Step 1: Write failing integration test — postflight formats lists**

Add to `NormalizationPipelineTests`:

```swift
    func test_postflight_formats_list_in_llm_output() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "во-первых скорость во-вторых простота",
            llmOutput: "во-первых скорость во-вторых простота",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "1. Скорость\n2. Простота")
    }

    func test_postflight_formats_list_with_relaxed_style() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "первое молоко второе хлеб",
            llmOutput: "первое молоко второе хлеб",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertEqual(result.finalText, "1. молоко\n2. хлеб")
    }

    func test_postflight_list_no_terminal_period() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "первое молоко второе хлеб",
            llmOutput: "первое молоко второе хлеб",
            contract: .normalization,
            superStyle: .formal,
            terminalPeriodEnabled: true
        )

        XCTAssertEqual(
            result.finalText,
            "1. Молоко\n2. Хлеб",
            "terminal period не применяется к list items"
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(test_postflight_formats_list|Test.*Failed)'`
Expected: fail — ListFormatter not wired into postflight.

- [ ] **Step 3: Wire ListFormatter into `postflight()`**

In `Govorun/Core/NormalizationPipeline.swift`, modify `postflight` (line 648-651):

```swift
        let effectiveTerminalPeriod = superStyle?.terminalPeriod ?? terminalPeriodEnabled
        let periodText = effectiveTerminalPeriod
            ? gateResult.output
            : DeterministicNormalizer.stripTrailingPeriods(gateResult.output)
        let styledText = superStyle?.applyDeterministic(periodText) ?? periodText
        let finalText = ListFormatter.format(styledText, style: superStyle)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E '(test_postflight_formats_list|Test.*Passed|Test.*Failed)'`
Expected: all pass.

- [ ] **Step 5: Verify terminal period test — formal list has no trailing period**

The test `test_postflight_list_no_terminal_period` checks that even in formal mode with `terminalPeriodEnabled: true`, list items don't get a trailing period. This works because:
1. `effectiveTerminalPeriod` keeps the period from `stripTrailingPeriods`
2. But `ListFormatter.cleanItem` strips trailing punctuation from every item

If the period sneaks through (i.e., the last item ends with `.`), verify `cleanItem` strips it. The implementation in Task 1 already strips trailing `.`, `,`, `;`.

- [ ] **Step 6: Commit**

```bash
git add Govorun/Core/NormalizationPipeline.swift GovorunTests/NormalizationPipelineTests.swift
git commit -m "feat: интегрировать ListFormatter в NormalizationPipeline.postflight"
```

---

### Task 6: Run full test suite, verify no regressions

**Files:** none (verification only)

- [ ] **Step 1: Run all Swift tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20`
Expected: all ~986+ tests pass, no regressions.

- [ ] **Step 2: Verify existing postflight tests still pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationPipelineTests 2>&1 | grep -E '(Test.*Passed|Test.*Failed)'`
Expected: all existing postflight tests pass unchanged.

- [ ] **Step 3: Verify standalone snippet verbatim contract**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/PipelineEngineTests/test_standalone_snippet_preserves_lowercase_verbatim 2>&1 | grep -E '(Test.*Passed|Test.*Failed)'`
Expected: passes.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: регрессии после интеграции ListFormatter"
```

Only run this if step 1-3 revealed failures that required fixes. Skip if all green.
