---
phase: 15-cloud-settings-ui
plan: 05
subsystem: ui
tags: [swiftui, design-system, statusdot, additive]

# Dependency graph
requires:
  - phase: 15-cloud-settings-ui
    provides: "design-system v2 tokens (Color.mist/sage/ember/ink) — уже смержены в main"
provides:
  - "StatusDot.State enum — idle / connected / error"
  - "StatusDot(title:state:) — новый state-based initializer"
  - "StatusDot(title:isActive:) — сохранён для обратной совместимости API"
  - "dot + text color логика под 3 состояния"
affects: [15-cloud-settings-ui]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Additive SwiftUI enum extension — новый API добавляется рядом с existing init, старый не удаляется"
    - "Нестатический `let state: State` + два init — convenience init pattern для обратной совместимости"
    - "switch-per-property (private var dotColor / textColor) — заменяет inline ternary"

key-files:
  created: []
  modified:
    - "Govorun/Views/SettingsTheme.swift — +35 / -3 строки в блоке `// MARK: - StatusDot`"

key-decisions:
  - "Сохранили `init(title:isActive:)` вопреки нулевому количеству call-sites — API stability convention проекта; `isActive: true` маппится в `.connected`, `false` → `.idle`"
  - "textColor выделен в отдельную private var (не ternary) — симметрия с dotColor, легче расширять при 4-й state"
  - "Error state окрашивает и dot (Ember), и текст (Ember) — остальные два держат Ink 0.5 per UI-SPEC §Color (row `Status line text`)"

patterns-established:
  - "StatusDot 3-state — основа для любого cloud-status indicator в Phase 15 и последующих"

requirements-completed: [UI-02]

# Metrics
duration: 8min
completed: 2026-04-20
---

# Phase 15 Plan 05: StatusDot 3-state Summary

**Additive расширение `StatusDot` в `SettingsTheme.swift` с 2-state (`isActive: Bool`) до 3-state (`State` enum: idle/connected/error) с сохранением исходного initializer.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-20T16:40:00Z
- **Completed:** 2026-04-20T16:48:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Добавлен вложенный `enum State { case idle, connected, error }` внутри `struct StatusDot`
- Введён новый `init(title: String, state: State)` — прямой state-based API для Plan 06
- Сохранён исходный `init(title: String, isActive: Bool)` — обратная совместимость: `isActive: true` → `.connected`, `false` → `.idle`
- Dot-цвет через `private var dotColor: Color` (Mist / Sage / Ember)
- Text-цвет через `private var textColor: Color` (Ink 0.5 для idle/connected; Ember для error) — per UI-SPEC §Color row «Status line text»
- `xcodebuild build -scheme Govorun -destination 'platform=macOS'` → **BUILD SUCCEEDED**
- Zero call-sites `StatusDot(title:` в `Govorun/` (ни до, ни после — confirmed via grep)

## Task Commits

Каждая задача закоммичена атомарно:

1. **Task 05-01: Extend StatusDot with State enum (additive)** — `7b14eb6` (feat)

_Plan 05 содержит единственную задачу — per plan frontmatter `tasks: 1 task` и execute-дисциплина._

## Files Created/Modified

- `Govorun/Views/SettingsTheme.swift` — расширен блок `// MARK: - StatusDot` (строки 120-170): добавлен enum State, два init, private var dotColor, private var textColor. Всё остальное в файле не тронуто.

## Decisions Made

- **Сохранили `init(title:isActive:)`** — хотя сегодня 0 call-sites (RESEARCH.md line 352), это API stability convention проекта (CLAUDE.md §Свойства Swift-кода); стоимость — 4 строки, выгода — zero-break гарантия при будущих reuse-случаях.
- **textColor как отдельная `private var`** — симметрично с `dotColor`; ternary `state == .error ? Ember : Ink 0.5` был коротким, но менее расширяемым при добавлении четвёртого состояния (warning, busy) в будущем.
- **Комментарии к enum cases на английском** (Mist dot / Sage dot / Ember) — per project convention комментарии «минимальные, на русском», но здесь технический токен-маппинг: English lowercase UI-design-system identifiers. Доктекст `/// Совместимость: ...` — на русском.

## Deviations from Plan

None — plan executed exactly as written.

План прописал точный срез кода (строки 104-152 в 15-05-PLAN.md); выполнил верибатим с двумя косметическими правками внутри бюджета плана:
1. switch-экспрессии записаны `case .idle: Color.mist` (без `return`) — SwiftUI-идиома Swift 5.9+, соответствует остальному стилю файла (см. `SectionHeader`, `BrandedButton`).
2. Комментарий `/// Backward-compat init: сохраняем...` русифицирован: `/// Совместимость: сохраняем...` — per CLAUDE.md («комментарии минимальные, на русском»).

## Issues Encountered

**Environment reset mid-execution (recovered):** первый проход Edit → запустил build (BUILD SUCCEEDED) → `git status` показал две модификации (SettingsTheme + SettingsStore от параллельного агента). После первой попытки коммита рабочее дерево было сброшено внешним хуком, все незакоммиченные изменения (включая мои) — откатились. Перечитал файл, повторил Edit верибатим, перестроил (BUILD SUCCEEDED), закоммитил только `Govorun/Views/SettingsTheme.swift`. Финальный результат корректен.

## User Setup Required

None — чистое UI-расширение, ноль внешних зависимостей, ноль новых tokens.

## Next Phase Readiness

Plan 06 может компоновать `StatusDot(title: "Подключено", state: .connected)`, `StatusDot(title: "Проверяю…", state: .idle)`, `StatusDot(title: cloudErrorMessage(for: err), state: .error)` — все три рендерятся согласно UI-SPEC §Color row `Status line text` и §Interaction States row #4.

Blockers: none.

## Self-Check

**Files modified present:**
- `Govorun/Views/SettingsTheme.swift` — FOUND (enum State, two inits, dotColor, textColor verified via grep)

**Commits:**
- `7b14eb6` — FOUND (git log --oneline: `feat(15-05): StatusDot 3-state (idle/connected/error)`)

**Build:** `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` → **BUILD SUCCEEDED**

**Acceptance criteria (grep-driven, per PLAN.md):**
- `enum State {` → 1 ✓
- `case idle` → 1 ✓
- `case connected` → 1 ✓
- `case error` → 1 ✓
- `init(title: String, isActive: Bool)` → 1 ✓
- `init(title: String, state: State)` → 1 ✓
- `Color.ember` → 2 (≥2 required) ✓
- `Color.sage` → 2 (≥1 required) ✓
- `Color.mist` → 5 (≥1 required) ✓
- Zero call-sites `StatusDot(title:` outside SettingsTheme.swift ✓

## Self-Check: PASSED

---
*Phase: 15-cloud-settings-ui*
*Completed: 2026-04-20*
