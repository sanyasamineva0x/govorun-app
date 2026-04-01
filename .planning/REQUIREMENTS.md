# Requirements: Стили текста v2

**Defined:** 2026-03-29
**Core Value:** Стиль текста адаптируется к контексту — расслабленный в мессенджерах, формальный в почте, обычный везде остальном

## v1 Requirements

### Стили текста (STYLE)

- [x] **STYLE-01**: SuperTextStyle enum (relaxed/normal/formal) с rawValue: String, CaseIterable
- [x] **STYLE-02**: Каждый стиль имеет computed properties: styleBlock, systemPrompt, contract, applyDeterministic
- [x] **STYLE-03**: LLMOutputContract enum (.normalization, .rewriting) — .rewriting как заглушка для 2.5
- [x] **STYLE-04**: SuperTextStyle.contract возвращает .normalization для всех трёх стилей (v2)
- [x] **STYLE-05**: applyDeterministic контролирует начальную капитализацию (relaxed → строчная, normal/formal → заглавная)

### Движок стилей (ENGINE)

- [x] **ENGINE-01**: SuperStyleEngine определяет стиль по bundleId в авто-режиме (жёсткий mapping из спеки)
- [x] **ENGINE-02**: SuperStyleEngine возвращает выбранный стиль в ручном режиме
- [x] **ENGINE-03**: Неизвестные bundleId → normal в авто-режиме
- [x] **ENGINE-04**: Авто-режим: relaxed для мессенджеров (Telegram, WhatsApp, Viber, VK, Messages, Discord)
- [x] **ENGINE-05**: Авто-режим: formal для почтовых клиентов (Mail, Spark, Outlook)

### Извлечение типов (EXTRACT)

- [x] **EXTRACT-01**: SnippetPlaceholder вынесен в Govorun/Models/SnippetPlaceholder.swift
- [x] **EXTRACT-02**: SnippetContext вынесен в Govorun/Models/SnippetContext.swift
- [x] **EXTRACT-03**: NormalizationHints вынесен в Govorun/Models/NormalizationHints.swift (без поля textMode)

### Pipeline интеграция (PIPE)

- [ ] **PIPE-01**: LLMClient.normalize(_:superStyle:hints:) — одна сигнатура, не перегрузка
- [ ] **PIPE-02**: LocalLLMClient использует SuperTextStyle.systemPrompt() для LLM запроса
- [ ] **PIPE-03**: PipelineEngine хранит _superStyle: SuperTextStyle? вместо _textMode
- [ ] **PIPE-04**: PipelineResult.superStyle: SuperTextStyle? вместо textMode: TextMode

### Gate модернизация (GATE)

- [x] **GATE-01**: NormalizationGate.evaluate(input:output:contract:superStyle:) — две оси
- [x] **GATE-02**: Style-aware protected tokens: в relaxed обе формы brand/tech aliases валидны
- [x] **GATE-03**: Edit distance нормализует к style-neutral form перед подсчётом
- [x] **GATE-04**: В formal — slang expansions (спс↔спасибо) валидны как protected tokens

### Postflight (POST)

- [x] **POST-01**: Если superStyle != nil — стиль определяет точку (relaxed/normal → без, formal → с)
- [x] **POST-02**: Если superStyle == nil (classic) — terminalPeriodEnabled из настроек

### Данные и настройки (DATA)

- [x] **DATA-01**: SettingsStore: superStyleMode (.auto/.manual) с default .auto
- [x] **DATA-02**: SettingsStore: manualSuperStyle с default .normal
- [x] **DATA-03**: HistoryStore.save() использует result.superStyle?.rawValue ?? "none"
- [x] **DATA-04**: HistoryView показывает SuperTextStyle(rawValue:)?.displayName с fallback для legacy
- [x] **DATA-05**: UserDefaults: удалить defaultTextMode, register defaults для новых ключей

### Аналитика (ANALYTICS)

- [ ] **ANALYTICS-01**: События содержат effective_style (relaxed/normal/formal/none)
- [ ] **ANALYTICS-02**: События Super содержат style_selection_mode (auto/manual)
- [ ] **ANALYTICS-03**: product_mode (standard/super) и detected_app_bundle в событиях

### UI (UI)

- [ ] **UI-01**: Вкладка "Стиль текста" в menubar-меню на вкладке Говорун Супер
- [ ] **UI-02**: Сегмент Авто/Ручной; авто показывает текущий стиль серым ("Расслабленный · Telegram")
- [ ] **UI-03**: Ручной: три карточки стилей с описанием, чекмарк на выбранном
- [ ] **UI-04**: Без модели: пункт активен но серый, при нажатии — NSAlert с предложением скачать

### Удаление TextMode (DELETE)

- [ ] **DELETE-01**: Удалены файлы TextMode.swift и AppModeSettingsView.swift
- [ ] **DELETE-02**: Удалены AppModeOverriding протокол и UserDefaultsAppModeOverrides класс
- [ ] **DELETE-03**: AppContextEngine: AppContext без textMode, удалены defaultAppModes и resolveTextMode()
- [ ] **DELETE-04**: AppState: убран TextMode из handleActivated

### Тестирование (TEST)

- [x] **TEST-01**: Unit-тесты SuperTextStyle: enum, styleBlock, systemPrompt, applyDeterministic
- [x] **TEST-02**: Unit-тесты SuperStyleEngine: bundleId mapping, авто/ручной
- [x] **TEST-03**: Unit-тесты SettingsStore: superStyleMode, manualSuperStyle
- [x] **TEST-04**: Unit-тесты NormalizationGate: style-aware protected tokens, slang, edit distance
- [x] **TEST-05**: Unit-тесты NormalizationPipeline: postflight с SuperTextStyle
- [x] **TEST-06**: Миграция существующих тестов: MockLLMClient, AppContextEngineTests, HistoryStoreTests, SnippetEngineTests

## v2 Requirements (2.5)

### Rewriting Contract

- **REWRITE-01**: LLMOutputContract.rewriting с lenient gate (только NER + длина ±50%)
- **REWRITE-02**: formal.contract → .rewriting
- **REWRITE-03**: Морфологическое ты→Вы в formal
- **REWRITE-04**: Отдельный seed corpus для rewriting стиля

## Out of Scope

| Feature | Reason |
|---------|--------|
| Per-app style overrides | Спека явно исключает — глобальный авто/ручной |
| Onboarding для стилей | Только menubar вкладка, не критично для v1 |
| Новый seed corpus | Используем существующий, расширяем потом |
| UI-тесты стилей | Спека упоминает, но не в v1 scope — benchmark достаточно |
| Style-aware benchmark | Один input → три expected outputs — отдельный скоуп |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STYLE-01 | Phase 1 | Complete |
| STYLE-02 | Phase 1 | Complete |
| STYLE-03 | Phase 1 | Complete |
| STYLE-04 | Phase 1 | Complete |
| STYLE-05 | Phase 1 | Complete |
| ENGINE-01 | Phase 1 | Complete |
| ENGINE-02 | Phase 1 | Complete |
| ENGINE-03 | Phase 1 | Complete |
| ENGINE-04 | Phase 1 | Complete |
| ENGINE-05 | Phase 1 | Complete |
| EXTRACT-01 | Phase 2 | Complete |
| EXTRACT-02 | Phase 2 | Complete |
| EXTRACT-03 | Phase 2 | Complete |
| PIPE-01 | Phase 3 | Pending |
| PIPE-02 | Phase 3 | Pending |
| PIPE-03 | Phase 3 | Pending |
| PIPE-04 | Phase 3 | Pending |
| GATE-01 | Phase 4 | Complete |
| GATE-02 | Phase 4 | Complete |
| GATE-03 | Phase 4 | Complete |
| GATE-04 | Phase 4 | Complete |
| POST-01 | Phase 5 | Complete |
| POST-02 | Phase 5 | Complete |
| DATA-01 | Phase 6 | Complete |
| DATA-02 | Phase 6 | Complete |
| DATA-03 | Phase 6 | Complete |
| DATA-04 | Phase 6 | Complete |
| DATA-05 | Phase 6 | Complete |
| ANALYTICS-01 | Phase 7 | Pending |
| ANALYTICS-02 | Phase 7 | Pending |
| ANALYTICS-03 | Phase 7 | Pending |
| UI-01 | Phase 8 | Pending |
| UI-02 | Phase 8 | Pending |
| UI-03 | Phase 8 | Pending |
| UI-04 | Phase 8 | Pending |
| DELETE-01 | Phase 9 | Pending |
| DELETE-02 | Phase 9 | Pending |
| DELETE-03 | Phase 9 | Pending |
| DELETE-04 | Phase 9 | Pending |
| TEST-01 | Phase 1 | Complete |
| TEST-02 | Phase 1 | Complete |
| TEST-03 | Phase 6 | Complete |
| TEST-04 | Phase 4 | Complete |
| TEST-05 | Phase 5 | Complete |
| TEST-06 | Phase 3 | Complete |

**Coverage:**
- v1 requirements: 45 total
- Mapped to phases: 45
- Unmapped: 0

**Note:** TEST requirements distributed to their respective functional phases (TDD approach).

---
*Requirements defined: 2026-03-29*
*Last updated: 2026-03-29 after roadmap creation -- TEST requirements redistributed to functional phases*
