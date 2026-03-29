# Architecture Research

**Domain:** SuperTextStyle integration into Говорун normalization pipeline
**Researched:** 2026-03-29
**Confidence:** HIGH

## Standard Architecture

### System Overview — SuperTextStyle Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  ┌───────────────────┐  ┌──────────────────┐                │
│  │ SuperStyleMenuView│  │ SettingsStore     │                │
│  │ (авто/ручной)     │──│ superStyleMode    │                │
│  └───────────────────┘  │ manualSuperStyle  │                │
│                         └────────┬─────────┘                │
├──────────────────────────────────┼──────────────────────────┤
│                     Services Layer                           │
│  ┌──────────────────┐  ┌────────┴────────┐                  │
│  │ AppContextEngine │──│ SuperStyleEngine │                  │
│  │ (bundleId)       │  │ resolveStyle()   │                  │
│  └──────────────────┘  └────────┬────────┘                  │
│                                 │                            │
│  ┌──────────────────────────────┴────────────────────────┐  │
│  │              PipelineEngine                            │  │
│  │  _superStyle: SuperTextStyle?                         │  │
│  │                                                       │  │
│  │  DeterministicNormalizer → LocalLLMClient →            │  │
│  │  NormalizationGate → Postflight                       │  │
│  └───────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                      Models Layer                            │
│  ┌──────────────┐  ┌─────────────────┐  ┌───────────────┐  │
│  │SuperTextStyle│  │LLMOutputContract│  │PipelineResult │  │
│  │ .relaxed     │  │ .normalization  │  │ .superStyle   │  │
│  │ .normal      │  │ .rewriting(2.5) │  │               │  │
│  │ .formal      │  │                 │  │               │  │
│  └──────────────┘  └─────────────────┘  └───────────────┘  │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │SnippetPlaceholder│  │NormalizationHints│                 │
│  │ (из TextMode.swift)│ │ (без textMode)  │                 │
│  └──────────────────┘  └──────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Layer | Responsibility | Changes |
|-----------|-------|----------------|---------|
| `SuperTextStyle` | Models | Enum стилей + computed props (styleBlock, systemPrompt, contract, applyDeterministic) | NEW |
| `LLMOutputContract` | Models | Enum контрактов (.normalization, .rewriting заглушка) | NEW |
| `SuperStyleEngine` | Services | Resolve style: авто (bundleId→style) или ручной (из settings) | NEW |
| `SettingsStore` | Services | superStyleMode (.auto/.manual) + manualSuperStyle (.normal default) | MODIFY |
| `AppContextEngine` | Services | Возвращает bundleId/appName, теряет textMode/resolveTextMode | MODIFY |
| `LLMClient` | Core/Protocol | normalize(_:superStyle:hints:) — новая сигнатура | MODIFY |
| `LocalLLMClient` | Services | Использует SuperTextStyle.systemPrompt() для LLM запроса | MODIFY |
| `NormalizationGate` | Core | evaluate(input:output:contract:superStyle:) — две оси | MODIFY |
| `NormalizationPipeline` | Core | postflight(superStyle:) — стиль владеет точкой | MODIFY |
| `PipelineEngine` | Services | _superStyle вместо _textMode, orchestration | MODIFY |
| `PipelineResult` | Models | .superStyle: SuperTextStyle? вместо .textMode | MODIFY |
| `HistoryStore` | Services | Пишет superStyle?.rawValue ?? "none" | MODIFY |
| `AnalyticsEvent` | Services | effective_style, style_selection_mode | MODIFY |

## Data Flow

### Style Resolution Flow

```
User → Settings (авто/ручной)
              ↓
AppContextEngine.bundleId ──→ SuperStyleEngine.resolveStyle()
              ↓                          ↓
         bundleId              SettingsStore.superStyleMode
                                         ↓
                              ┌──── .auto ────┐
                              │               │
                    bundleId mapping     manualSuperStyle
                    (relaxed/normal/     (from settings)
                     formal)
                              │               │
                              └───── SuperTextStyle ─────┘
                                         ↓
                                    PipelineEngine
```

### Normalization Pipeline Flow (Super mode)

```
Input text
    ↓
DeterministicNormalizer (филлеры, числа, канон)
    ↓
SuperTextStyle.applyDeterministic(caps, точка) ← trivial path stops here
    ↓
LocalLLMClient.normalize(text, superStyle: style, hints: hints)
    ↓ (LLM uses systemPrompt + styleBlock)
LLM output
    ↓
NormalizationGate.evaluate(
    input: original,
    output: llmOutput,
    contract: style.contract,      ← ось 1: normalization vs rewriting
    superStyle: style              ← ось 2: какие замены валидны
)
    ↓ (pass/fail)
NormalizationPipeline.postflight(superStyle: style)
    ↓ (точка: relaxed/normal → убрать, formal → добавить)
Final text → TextInserter
```

### Two-Axis Gate Design

```
                    contract (масштаб изменений)
                    ┌─────────────────┬──────────────────┐
                    │  .normalization │  .rewriting (2.5) │
                    │  strict dist    │  lenient          │
    ┌───────────────┼─────────────────┼──────────────────┤
    │ .relaxed      │ бренды кирилл.  │       —          │
s   │               │ техтермины кир. │                  │
t   │               │ strict distance │                  │
y   ├───────────────┼─────────────────┼──────────────────┤
l   │ .normal       │ стандартные     │       —          │
e   │               │ проверки        │                  │
    ├───────────────┼─────────────────┼──────────────────┤
    │ .formal       │ сленг раскрыт   │  переписывание   │
    │               │ strict distance │  lenient (2.5)   │
    ├───────────────┼─────────────────┼──────────────────┤
    │ nil (classic)  │ как раньше      │       —          │
    └───────────────┴─────────────────┴──────────────────┘
```

## Architectural Patterns

### Pattern 1: Bottom-Up Type Introduction

**What:** Создать foundation типы (SuperTextStyle, LLMOutputContract) до интеграции
**When to use:** Всегда при breaking enum changes — типы должны компилироваться изолированно
**Trade-offs:** Проект не компилируется пока не обновлены все ссылки → решение: оба enum существуют параллельно временно

### Pattern 2: Protocol Boundary as Seam

**What:** LLMClient протокол — точка разреза для обновления сигнатуры
**When to use:** Менять протокол + все реализации + все моки одновременно
**Trade-offs:** Большой PR section, но атомарный — нет промежуточного broken state

### Pattern 3: nil-as-Classic

**What:** `SuperTextStyle?` — nil означает classic mode (без Super стилей)
**When to use:** Везде где pipeline должен различать classic/super
**Trade-offs:** Optional unwrapping vs отдельный enum case `.none` — optional проще, потому что classic не участвует в style logic

### Pattern 4: Extract Before Delete

**What:** Вынести SnippetPlaceholder, SnippetContext, NormalizationHints из TextMode.swift ДО удаления файла
**When to use:** Когда файл содержит переиспользуемые типы вместе с удаляемым
**Trade-offs:** Лишний шаг, но предотвращает потерю типов при удалении

## Suggested Build Order

Фазы строятся снизу вверх — от фундаментальных типов к интеграции:

1. **Foundation types** — SuperTextStyle, LLMOutputContract, SuperStyleEngine
2. **Extract types** — вынести SnippetPlaceholder, SnippetContext, NormalizationHints из TextMode.swift
3. **Pipeline integration** — LLMClient сигнатура, LocalLLMClient, PipelineEngine
4. **Gate modernization** — NormalizationGate с двумя осями, protected tokens, edit distance
5. **Postflight** — стиль владеет точкой
6. **Settings & data** — SettingsStore, HistoryStore, PipelineResult, UserDefaults migration
7. **Analytics** — effective_style, style_selection_mode
8. **UI** — вкладка "Стиль текста" в menubar
9. **TextMode deletion** — удалить enum, файлы, протоколы, обновить AppContextEngine
10. **Test migration** — обновить все тесты на SuperTextStyle

### Build Order Rationale

- Types first (1) → используются во всех последующих фазах
- Extract before delete (2) → зависимые типы должны быть на месте до удаления TextMode
- Pipeline (3) → основной data flow, блокирует gate и postflight
- Gate (4) → зависит от SuperTextStyle и LLMOutputContract
- Deletion last (9) → все ссылки на TextMode уже заменены
- Tests last (10) → нужны все production changes для обновления моков

## Anti-Patterns

### Anti-Pattern 1: Parallel API Period

**What people do:** Оставляют старый TextMode API рядом с новым SuperTextStyle
**Why it's wrong:** Два параллельных пути = путаница, забытые ветки, тесты дублируются
**Do this instead:** Atomic replacement: каждая фаза полностью заменяет TextMode в своей области

### Anti-Pattern 2: Incremental Gate Modification

**What people do:** Модифицируют gate по одному параметру за раз
**Why it's wrong:** Gate с частичной style-awareness даёт false rejections
**Do this instead:** Обновить gate целиком: contract + superStyle + protected tokens + edit distance normalization

### Anti-Pattern 3: SwiftData Migration

**What people do:** Создают SwiftData model version migration для смены значений
**Why it's wrong:** Поле String, значения меняются — migration не нужна, только усложнит
**Do this instead:** Старые значения остаются legacy, новые пишутся, UI делает fallback

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| SuperStyleEngine ↔ AppContextEngine | bundleId (String) | Только чтение bundleId, style resolution в SuperStyleEngine |
| SuperStyleEngine ↔ SettingsStore | @Published properties | Reactive binding для UI |
| PipelineEngine ↔ LLMClient | normalize(_:superStyle:hints:) | Один вызов, синхронная замена сигнатуры |
| PipelineEngine ↔ NormalizationGate | evaluate(input:output:contract:superStyle:) | Два новых параметра |
| HistoryStore ↔ PipelineResult | superStyle?.rawValue ?? "none" | String serialization |

---
*Architecture research for: SuperTextStyle integration*
*Researched: 2026-03-29*
