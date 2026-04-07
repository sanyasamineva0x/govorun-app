# Formal ты→вы Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Деловой стиль (formal) в Super mode переводит ты→вы и согласует глаголы, сохраняя лексику.

**Architecture:** Переключить `formal.contract` с `.normalization` на существующий `.rewriting` (без edit distance, только protected tokens + length ratio). Обновить промпт: ты→вы + явный запрет лексических замен.

**Tech Stack:** Swift 5.10, XCTest, TDD

**Spec:** `docs/superpowers/specs/2026-04-06-formal-rewriting-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Govorun/Models/SuperTextStyle.swift:32-34` | `formal.contract` → `.rewriting` |
| Modify | `Govorun/Models/SuperTextStyle.swift:117-127` | Обновить `styleBlock` для formal |
| Modify | `GovorunTests/SuperTextStyleTests.swift` | Тесты: contract == .rewriting, styleBlock содержит «ВЫ» и «ЗАПРЕТ» |
| Modify | `GovorunTests/NormalizationGateTests.swift` | Тесты: `.rewriting` + formal ты→вы |
| Modify | `GovorunTests/NormalizationPipelineTests.swift` | Интеграционный тест: postflight formal принимает ты→вы |
| Modify | `benchmarks/llm-normalization-seed.jsonl` | 15 benchmark-кейсов для formal |

---

### Task 1: Switch formal contract to `.rewriting`

**Files:**
- Modify: `Govorun/Models/SuperTextStyle.swift:32-34`
- Modify: `GovorunTests/SuperTextStyleTests.swift`

- [ ] **Step 1: Write failing test for formal contract**

Add to `SuperTextStyleTests`:

```swift
    // MARK: - Contract

    func test_formal_contract_is_rewriting() {
        XCTAssertEqual(SuperTextStyle.formal.contract, .rewriting)
    }

    func test_normal_contract_is_normalization() {
        XCTAssertEqual(SuperTextStyle.normal.contract, .normalization)
    }

    func test_relaxed_contract_is_normalization() {
        XCTAssertEqual(SuperTextStyle.relaxed.contract, .normalization)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests/test_formal_contract_is_rewriting 2>&1 | tail -10`
Expected: FAIL — formal.contract currently returns `.normalization`.

- [ ] **Step 3: Switch formal contract**

In `Govorun/Models/SuperTextStyle.swift`, change `contract` property (line 32-34) from:

```swift
    var contract: LLMOutputContract {
        .normalization
    }
```

to:

```swift
    var contract: LLMOutputContract {
        switch self {
        case .relaxed, .normal: .normalization
        case .formal: .rewriting
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Govorun/Models/SuperTextStyle.swift GovorunTests/SuperTextStyleTests.swift
git commit -m "feat: formal contract → .rewriting для поддержки ты→вы"
```

---

### Task 2: Update formal styleBlock prompt

**Files:**
- Modify: `Govorun/Models/SuperTextStyle.swift:117-127`
- Modify: `GovorunTests/SuperTextStyleTests.swift`

- [ ] **Step 1: Write failing tests for new styleBlock content**

Add to `SuperTextStyleTests`:

```swift
    func test_style_block_formal_you_form() {
        let block = SuperTextStyle.formal.styleBlock
        XCTAssertTrue(block.contains("ОБРАЩЕНИЕ НА «ВЫ»"))
    }

    func test_style_block_formal_lexical_prohibition() {
        let block = SuperTextStyle.formal.styleBlock
        XCTAssertTrue(block.contains("ЗАПРЕТ"))
        XCTAssertTrue(block.contains("не заменяй лексику"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests/test_style_block_formal_you_form 2>&1 | tail -10`
Expected: FAIL — current styleBlock contains "ОБРАЩЕНИЕ:", not "ОБРАЩЕНИЕ НА «ВЫ»".

- [ ] **Step 3: Replace formal styleBlock**

In `Govorun/Models/SuperTextStyle.swift`, replace the formal case in `styleBlock` (lines 117-127) from:

```swift
        case .formal:
            return """
            Стиль: деловой, вежливый. Заглавная буква в начале. Точка в конце. \
            Транслитерация: бренды и техтермины → оригинальное написание (Slack, Zoom, Jira, PDF, API). \
            Сленг раскрывать в полные формы (норм → нормально, спс → спасибо, ок → хорошо).
            ОБРАЩЕНИЕ: замени «ты/тебе/тебя/твой» на «вы/вам/вас/ваш», согласуй глаголы \
            (можешь → можете, сделай → сделайте, скинь → скиньте).
            ДЕЛОВЫЕ ОБОРОТЫ: надо/нужно → необходимо, хочу → хотел бы, не могу → к сожалению, не смогу.
            ИМПЕРАТИВЫ: смягчай прямые приказы → вежливые просьбы \
            (сделай отчёт → Прошу подготовить отчёт, перенеси встречу → Прошу перенести встречу).
            """
```

to:

```swift
        case .formal:
            return """
            Стиль: деловой, вежливый. Заглавная буква в начале. Точка в конце. \
            Транслитерация: бренды и техтермины → оригинальное написание (Slack, Zoom, Jira, PDF, API). \
            Сленг раскрывать в полные формы (норм → нормально, спс → спасибо, ок → хорошо).
            ОБРАЩЕНИЕ НА «ВЫ»: замени «ты/тебе/тебя/тобой/твой» на «вы/вам/вас/вами/ваш», \
            согласуй глаголы (можешь → можете, сделай → сделайте, скинь → скиньте, \
            сделал → сделали, пришёл → пришли).
            ЗАПРЕТ: кроме обращения на «вы» и грамматического согласования — не заменяй лексику, \
            не смягчай тон, не добавляй деловые обороты, не перефразируй целиком. \
            «скинь» → «скиньте», НЕ «направьте». «скажи» → «скажите», НЕ «сообщите».
            """
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -10`
Expected: all pass. Existing tests `test_style_block_formal_slang_expansion` and `test_style_block_formal_original_brands` still pass because the new text preserves those strings.

- [ ] **Step 5: Commit**

```bash
git add Govorun/Models/SuperTextStyle.swift GovorunTests/SuperTextStyleTests.swift
git commit -m "feat: промпт formal ты→вы с запретом лексических замен"
```

---

### Task 3: Gate tests for `.rewriting` with formal ты→вы

**Files:**
- Modify: `GovorunTests/NormalizationGateTests.swift`

- [ ] **Step 1: Write tests for `.rewriting` + formal style**

Add to `NormalizationGateTests`:

```swift
    // MARK: - GATE-05: formal ты→вы через .rewriting

    func test_rewriting_accepts_ty_to_vy_transformation() {
        let result = NormalizationGate.evaluate(
            input: "Ты можешь скинуть отчёт до пятницы.",
            output: "Вы можете скинуть отчёт до пятницы.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Вы можете скинуть отчёт до пятницы.")
    }

    func test_rewriting_accepts_imperative_te_form() {
        let result = NormalizationGate.evaluate(
            input: "Скажи Пете, что встреча перенеслась.",
            output: "Скажите Пете, что встреча перенеслась.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_accepts_possessive_replacement() {
        let result = NormalizationGate.evaluate(
            input: "Перешли ей твой отчёт за март.",
            output: "Перешлите ей ваш отчёт за март.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_preserves_protected_tokens() {
        let result = NormalizationGate.evaluate(
            input: "Ты получил моё письмо от 25 марта в Slack.",
            output: "Вы получили моё письмо от 25 марта в Slack.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_rejects_missing_protected_token() {
        let result = NormalizationGate.evaluate(
            input: "Ты получил моё письмо от 25 марта в Slack.",
            output: "Вы получили моё письмо от марта.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
    }

    func test_rewriting_rejects_empty_output() {
        let result = NormalizationGate.evaluate(
            input: "Скажи пете что встреча перенеслась.",
            output: "",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.failureReason, .empty)
    }

    func test_rewriting_does_not_reverse_vy() {
        let result = NormalizationGate.evaluate(
            input: "Вы можете отправить документ.",
            output: "Вы можете отправить документ.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Вы можете отправить документ.")
    }
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateTests 2>&1 | tail -10`
Expected: all pass — `.rewriting` contract already handles these correctly.

- [ ] **Step 3: Commit**

```bash
git add GovorunTests/NormalizationGateTests.swift
git commit -m "test: gate тесты для .rewriting + formal ты→вы"
```

---

### Task 4: Integration test — postflight formal accepts ты→вы

**Files:**
- Modify: `GovorunTests/NormalizationPipelineTests.swift`

- [ ] **Step 1: Write integration tests**

Add to `NormalizationPipelineTests`:

```swift
    // MARK: - Formal ты→вы через .rewriting

    func test_postflight_formal_accepts_ty_to_vy() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Ты можешь скинуть отчёт до пятницы.",
            llmOutput: "Вы можете скинуть отчёт до пятницы.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertEqual(result.finalText, "Вы можете скинуть отчёт до пятницы.")
        XCTAssertEqual(result.path, .llm)
    }

    func test_postflight_formal_preserves_lexicon() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Скинь отчёт.",
            llmOutput: "Скиньте отчёт.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertEqual(
            result.finalText,
            "Скиньте отчёт.",
            "скинь→скиньте, лексика сохранена — gate не должен reject'ить"
        )
        XCTAssertEqual(result.path, .llm)
    }
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationPipelineTests 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add GovorunTests/NormalizationPipelineTests.swift
git commit -m "test: интеграционный тест formal ты→вы через postflight"
```

---

### Task 5: Benchmark cases

**Files:**
- Modify: `benchmarks/llm-normalization-seed.jsonl`

- [ ] **Step 1: Add 15 formal benchmark cases**

Append to `benchmarks/llm-normalization-seed.jsonl`:

```jsonl
{"id":"formal-001","bucket":"formal-positive","input":"ты можешь скинуть отчёт до пятницы","expected":"Вы можете скинуть отчёт до пятницы.","style":"formal"}
{"id":"formal-002","bucket":"formal-positive","input":"скажи пете что встреча перенеслась","expected":"Скажите Пете, что встреча перенеслась.","style":"formal"}
{"id":"formal-003","bucket":"formal-positive","input":"проверь пожалуйста документ и скинь мне","expected":"Проверьте, пожалуйста, документ и скиньте мне.","style":"formal"}
{"id":"formal-004","bucket":"formal-positive","input":"напиши маше что дедлайн в пятницу","expected":"Напишите Маше, что дедлайн в пятницу.","style":"formal"}
{"id":"formal-005","bucket":"formal-positive","input":"ты сегодня свободен в 15:30","expected":"Вы сегодня свободны в 15:30.","style":"formal"}
{"id":"formal-006","bucket":"formal-positive","input":"перешли ей твой отчёт за март","expected":"Перешлите ей ваш отчёт за март.","style":"formal"}
{"id":"formal-007","bucket":"formal-positive","input":"ты получил моё письмо от 25 марта в слак","expected":"Вы получили моё письмо от 25 марта в Slack.","style":"formal"}
{"id":"formal-008","bucket":"formal-positive","input":"позвони клиенту и уточни сроки а потом напиши мне","expected":"Позвоните клиенту и уточните сроки, а потом напишите мне.","style":"formal"}
{"id":"formal-009","bucket":"formal-positive","input":"я хочу чтобы ты подготовил презентацию и отправил её пете","expected":"Я хочу, чтобы вы подготовили презентацию и отправили её Пете.","style":"formal"}
{"id":"formal-010","bucket":"formal-positive","input":"спс скинь в слак ссылку на задачу в жире","expected":"Спасибо, скиньте в Slack ссылку на задачу в Jira.","style":"formal"}
{"id":"formal-011","bucket":"formal-negative","input":"скинь отчёт","expected":"Скиньте отчёт.","style":"formal"}
{"id":"formal-012","bucket":"formal-negative","input":"скажи ему что я опоздаю","expected":"Скажите ему, что я опоздаю.","style":"formal"}
{"id":"formal-013","bucket":"formal-negative","input":"привет ты можешь помочь","expected":"Привет, вы можете помочь.","style":"formal"}
{"id":"formal-014","bucket":"formal-negative","input":"вы можете отправить документ","expected":"Вы можете отправить документ.","style":"formal"}
{"id":"formal-015","bucket":"formal-negative","input":"подготовьте отчёт к пятнице","expected":"Подготовьте отчёт к пятнице.","style":"formal"}
```

- [ ] **Step 2: Commit**

```bash
git add benchmarks/llm-normalization-seed.jsonl
git commit -m "test: 15 benchmark-кейсов formal ты→вы (positive + negative)"
```

---

### Task 6: Full test suite, verify no regressions

**Files:** none (verification only)

- [ ] **Step 1: Run all Swift tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20`
Expected: all tests pass, no regressions. Key tests to watch:
- `test_postflight_formal_keeps_period` — must still pass (formal adds period)
- `test_formal_accepts_slang_expansion_as_protected_token` — must still pass
- `test_formal_rejects_unknown_slang` — **may need attention**: this test uses `.normalization` contract. With formal now returning `.rewriting`, the test's contract should match. Check if this test constructs its own contract or uses `formal.contract`.

- [ ] **Step 2: Fix any regressions**

If `test_formal_rejects_unknown_slang` or similar tests fail because they relied on `formal.contract == .normalization`, update them to pass the correct contract explicitly. The gate tests should test contracts directly, not through `formal.contract`.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: регрессии после переключения formal на .rewriting"
```

Only run if regressions found. Skip if all green.
