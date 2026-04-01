# Roadmap: Стили текста v2

## Overview

Замена TextMode на SuperTextStyle по всему pipeline Говоруна. Строим снизу вверх: foundation types (enum + engine) --> извлечение типов из TextMode.swift --> pipeline integration --> gate modernization --> postflight --> settings/data --> analytics --> UI --> удаление TextMode. Каждая фаза оставляет проект компилируемым. Тесты пишутся внутри каждой фазы (TDD), не в отдельной фазе.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation Types** - SuperTextStyle enum, LLMOutputContract, SuperStyleEngine с тестами
- [ ] **Phase 2: Type Extraction** - Вынос SnippetPlaceholder, SnippetContext, NormalizationHints из TextMode.swift
- [ ] **Phase 3: Pipeline Integration** - LLMClient новая сигнатура, PipelineEngine на SuperTextStyle, миграция тестов
- [ ] **Phase 4: Gate Modernization** - Двухосевой evaluate, style-aware protected tokens, edit distance
- [ ] **Phase 5: Postflight** - Стиль владеет точкой, applyDeterministic caps
- [ ] **Phase 6: Settings & Data** - SettingsStore, HistoryStore, PipelineResult, UserDefaults миграция
- [ ] **Phase 7: Analytics** - effective_style, style_selection_mode, product_mode в событиях
- [ ] **Phase 8: UI** - Вкладка "Стиль текста" в menubar (авто/ручной, карточки, без модели)
- [ ] **Phase 9: TextMode Deletion** - Удаление TextMode.swift, AppModeSettingsView, протоколов, очистка AppContextEngine

## Phase Details

### Phase 1: Foundation Types
**Goal**: Новые типы стилей существуют и полностью протестированы -- все downstream фазы могут на них опираться
**Depends on**: Nothing (first phase)
**Requirements**: STYLE-01, STYLE-02, STYLE-03, STYLE-04, STYLE-05, ENGINE-01, ENGINE-02, ENGINE-03, ENGINE-04, ENGINE-05, TEST-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. SuperTextStyle enum (relaxed/normal/formal) компилируется и предоставляет styleBlock, systemPrompt, contract, applyDeterministic
  2. LLMOutputContract enum (.normalization, .rewriting) существует; все три стиля возвращают .normalization
  3. SuperStyleEngine в авто-режиме возвращает relaxed для мессенджеров, formal для почты, normal для неизвестных bundleId
  4. SuperStyleEngine в ручном режиме возвращает выбранный стиль независимо от bundleId
  5. Unit-тесты покрывают SuperTextStyle (enum, properties) и SuperStyleEngine (авто/ручной mapping)
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- SuperTextStyle enum, SuperStyleMode, alias tables, computed properties, systemPrompt, тесты
- [x] 01-02-PLAN.md -- SuperStyleEngine bundleId resolution, тесты, полная верификация suite

### Phase 2: Type Extraction
**Goal**: Типы, живущие сейчас в TextMode.swift, вынесены в отдельные файлы -- TextMode.swift можно безопасно удалить позже
**Depends on**: Phase 1
**Requirements**: EXTRACT-01, EXTRACT-02, EXTRACT-03
**Success Criteria** (what must be TRUE):
  1. SnippetPlaceholder, SnippetContext, NormalizationHints существуют в отдельных файлах Models/
  2. NormalizationHints не содержит поля textMode
  3. Проект компилируется, все 986+ тестов проходят без изменений
**Plans**: 1 plan

Plans:
- [x] 02-01-PLAN.md -- Extract SnippetPlaceholder, SnippetContext, NormalizationHints; remove textMode from hints; update consumers

### Phase 3: Pipeline Integration
**Goal**: Pipeline использует SuperTextStyle вместо TextMode для LLM запросов -- данные текут через новую сигнатуру
**Depends on**: Phase 1, Phase 2
**Requirements**: PIPE-01, PIPE-02, PIPE-03, PIPE-04, TEST-06
**Success Criteria** (what must be TRUE):
  1. LLMClient.normalize(_:superStyle:hints:) -- единственная сигнатура нормализации
  2. LocalLLMClient формирует LLM запрос используя SuperTextStyle.systemPrompt()
  3. PipelineEngine хранит и прокидывает SuperTextStyle вместо TextMode
  4. PipelineResult.superStyle: SuperTextStyle? доступен вместо textMode
  5. MockLLMClient, AppContextEngineTests, HistoryStoreTests, SnippetEngineTests обновлены и проходят
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- LLMClient + LocalLLMClient + PipelineEngine + NormalizationPipeline + AppState + HistoryStore production code migration
- [ ] 03-02-PLAN.md -- MockLLMClient + test files migration, full suite verification

### Phase 4: Gate Modernization
**Goal**: NormalizationGate валидирует LLM-выход с учётом стиля -- false rejections для style transforms исключены
**Depends on**: Phase 1, Phase 3
**Requirements**: GATE-01, GATE-02, GATE-03, GATE-04, TEST-04
**Success Criteria** (what must be TRUE):
  1. NormalizationGate.evaluate принимает contract и superStyle как отдельные оси
  2. В relaxed обе формы brand/tech aliases (Slack/слак, PDF/пдф) считаются валидными protected tokens
  3. В formal slang expansions (спс/спасибо) считаются валидными protected tokens
  4. Edit distance нормализует style aliases перед подсчётом (style-neutral)
  5. Unit-тесты покрывают style-aware protected tokens, slang, edit distance для всех трёх стилей
**Plans**: 2 plans

Plans:
- [x] 04-01-PLAN.md -- Style-aware gate: slangExpansions table, TDD tests, alias-aware protected tokens, style-neutral edit distance, threshold relaxation
- [x] 04-02-PLAN.md -- Wire superStyle through PipelineEngine and NormalizationPipeline call sites

### Phase 5: Postflight
**Goal**: Финальная обработка текста (точка, капитализация) определяется стилем -- детерминированное поведение для каждого уровня формальности
**Depends on**: Phase 1, Phase 3
**Requirements**: POST-01, POST-02, TEST-05
**Success Criteria** (what must be TRUE):
  1. При superStyle != nil стиль определяет точку: relaxed/normal без точки, formal с точкой
  2. При superStyle == nil (classic) точка определяется terminalPeriodEnabled из настроек
  3. Unit-тесты постфлайта покрывают все комбинации стиль/classic x точка
**Plans**: 1 plan

Plans:
- [x] 05-01-PLAN.md -- terminalPeriod property, style-aware postflight period+caps, effectiveTerminalPeriod in PipelineEngine, TDD tests

### Phase 6: Settings & Data
**Goal**: Настройки стилей и история сохраняются корректно -- пользователь может переключать авто/ручной и видеть стиль в истории
**Depends on**: Phase 1, Phase 3
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, TEST-03
**Success Criteria** (what must be TRUE):
  1. SettingsStore предоставляет superStyleMode (.auto/.manual) с default .auto и manualSuperStyle с default .normal
  2. HistoryStore.save() записывает result.superStyle?.rawValue, HistoryView показывает displayName с fallback для legacy
  3. UserDefaults: defaultTextMode удалён, новые defaults зарегистрированы ДО первого чтения
  4. Unit-тесты SettingsStore покрывают superStyleMode и manualSuperStyle
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

### Phase 7: Analytics
**Goal**: События аналитики содержат информацию о стиле -- метрики стилей доступны ДО удаления TextMode
**Depends on**: Phase 3, Phase 6
**Requirements**: ANALYTICS-01, ANALYTICS-02, ANALYTICS-03
**Success Criteria** (what must be TRUE):
  1. Аналитические события содержат effective_style (relaxed/normal/formal/none)
  2. События Super содержат style_selection_mode (auto/manual)
  3. product_mode и detected_app_bundle присутствуют в событиях
**Plans**: TBD

Plans:
- [ ] 07-01: TBD

### Phase 8: UI
**Goal**: Пользователь может переключать стили в menubar -- авто/ручной режим с визуальным feedback
**Depends on**: Phase 1, Phase 6
**Requirements**: UI-01, UI-02, UI-03, UI-04
**Success Criteria** (what must be TRUE):
  1. Вкладка "Стиль текста" присутствует в menubar-меню на странице Говорун Супер
  2. Сегмент Авто/Ручной работает; авто показывает текущий стиль серым ("Расслабленный . Telegram")
  3. В ручном режиме три карточки стилей с описаниями, чекмарк на выбранном
  4. Без модели: пункт активен но серый, при нажатии NSAlert с предложением скачать
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 08-01: TBD
- [ ] 08-02: TBD

### Phase 9: TextMode Deletion
**Goal**: TextMode и вся его инфраструктура удалены -- единственная система стилей в проекте это SuperTextStyle
**Depends on**: Phase 3, Phase 4, Phase 5, Phase 6, Phase 7, Phase 8
**Requirements**: DELETE-01, DELETE-02, DELETE-03, DELETE-04
**Success Criteria** (what must be TRUE):
  1. TextMode.swift и AppModeSettingsView.swift удалены из проекта
  2. AppModeOverriding протокол и UserDefaultsAppModeOverrides класс удалены
  3. AppContextEngine: AppContext не содержит textMode, методы defaultAppModes и resolveTextMode() удалены
  4. AppState: TextMode не упоминается в handleActivated
  5. Проект компилируется, все тесты проходят без ссылок на TextMode
**Plans**: TBD

Plans:
- [ ] 09-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 --> 2 --> 3 --> 4 --> 5 --> 6 --> 7 --> 8 --> 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation Types | 0/2 | Not started | - |
| 2. Type Extraction | 0/1 | Not started | - |
| 3. Pipeline Integration | 0/2 | Not started | - |
| 4. Gate Modernization | 2/2 | Complete | 2026-03-31 |
| 5. Postflight | 1/1 | Complete | 2026-04-01 |
| 6. Settings & Data | 0/2 | Not started | - |
| 7. Analytics | 0/1 | Not started | - |
| 8. UI | 0/2 | Not started | - |
| 9. TextMode Deletion | 0/1 | Not started | - |
