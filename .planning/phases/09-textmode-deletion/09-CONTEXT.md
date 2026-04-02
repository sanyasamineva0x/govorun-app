# Phase 9: TextMode Deletion - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Удаление TextMode enum и всей его инфраструктуры. После этой фазы единственная система стилей — SuperTextStyle. Проект компилируется, все тесты проходят.

</domain>

<decisions>
## Implementation Decisions

### Файлы на полное удаление
- **D-01:** Удалить `Govorun/Models/TextMode.swift` (188 строк) — весь enum TextMode
- **D-02:** Удалить `Govorun/Views/AppModeSettingsView.swift` (180 строк) — UI для TextMode overrides
- **D-03:** Удалить `Govorun/App/NSWorkspaceProvider.swift` — `UserDefaultsAppModeOverrides` и `WorkspaceProviding` протокол (только для TextMode)

### AppContextEngine — рефакторинг, не полное удаление
- **D-04:** `AppContextEngine` нельзя удалить целиком — `detectCurrentApp()` возвращает `bundleId`, который нужен для SuperStyleEngine (авто-режим) и аналитики. Удалить: `textMode` поле из `AppContext`, `defaultAppModes` словарь, `resolveTextMode()` метод, `AppModeOverriding` протокол. Оставить: `bundleId` detection через `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`

### HistoryView — отображение старых записей
- **D-05:** Старые записи с TextMode значениями ("chat", "email" и т.д.) — бейдж стиля НЕ выводить. Показывать стиль только когда `SuperTextStyle(rawValue:)` успешно распознаёт значение.

### HistoryStore — запись стиля
- **D-06:** Продолжать писать `superStyle?.rawValue ?? "none"` в поле `textMode` при сохранении. Новые записи будут с корректным стилем.

### HistoryItem — backward compatibility
- **D-07:** Поле `textMode: String` в `HistoryItem` НЕ удалять — SwiftData migration не нужна (из PROJECT.md).

### Хирургические правки
- **D-08:** `NormalizationGate.swift` — удалить extension `TextMode { var llmOutputContract }` (мёртвый код)
- **D-09:** `AppState.swift` — удалить `textMode` из аналитики metadata, обновить wiring `AppContextEngine` (убрать `AppModeOverriding`)
- **D-10:** `AnalyticsEvent.swift` — удалить `static let textMode = "text_mode"`
- **D-11:** `SettingsTheme.swift` — удалить `case appModes` из `SettingsSection` enum и `visibleCases`

### Claude's Discretion
- Порядок удаления файлов и правок
- Структура тестовых правок (какие тест-файлы задеты)
- Нужен ли `xcodegen generate` после удаления файлов

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей v2 — секция удаления
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — полная спека включая секцию удаления TextMode

### Файлы на удаление (полное)
- `Govorun/Models/TextMode.swift` — enum TextMode, 188 строк, DELETE
- `Govorun/Views/AppModeSettingsView.swift` — UI оверрайдов TextMode, 180 строк, DELETE
- `Govorun/App/NSWorkspaceProvider.swift` — UserDefaultsAppModeOverrides + WorkspaceProviding, DELETE

### Файлы на хирургическую правку
- `Govorun/Core/AppContextEngine.swift` — удалить textMode из AppContext, оставить bundleId detection
- `Govorun/Core/NormalizationGate.swift` — удалить TextMode extension (строки ~10-17)
- `Govorun/App/AppState.swift` — строка 836 detectCurrentApp(), строка 862 textMode в аналитике
- `Govorun/Models/AnalyticsEvent.swift` — строка 57 textMode key
- `Govorun/Views/HistoryView.swift` — строки ~112-116 TextMode display fallback
- `Govorun/Views/SettingsTheme.swift` — case appModes в SettingsSection

### Файлы НЕ трогать
- `Govorun/Models/HistoryItem.swift` — textMode поле остаётся (backward compat)
- `Govorun/Storage/HistoryStore.swift` — запись textMode остаётся (D-06)

</canonical_refs>

<code_context>
## Existing Code Insights

### Масштаб удаления
- 4 файла на полное удаление (~503 строки)
- 6 файлов на хирургическую правку (~14 строк)
- ~20+ тестовых файлов могут содержать ссылки на TextMode

### Критические зависимости
- `AppState` инициализирует `AppContextEngine` с `workspace` и `overrides` параметрами — после удаления overrides нужно упростить
- `SuperStyleEngine.resolve(bundleId:mode:manualStyle:)` — НЕ зависит от AppContextEngine, получает bundleId как параметр
- `PipelineEngine` может содержать ссылки на TextMode (Phase 3 pipeline integration)

### Тестовая инфраструктура
- `GovorunTests/` содержит ~38 файлов, нужно проверить каждый на TextMode ссылки
- Моки `AppContextEngine` и `AppModeOverriding` в тестах — удалить или заменить

</code_context>

<specifics>
## Specific Ideas

- Удаление в два плана: (1) удаление файлов + хирургические правки, (2) очистка тестов
- `xcodegen generate` обязателен после удаления .swift файлов

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-textmode-deletion*
*Context gathered: 2026-04-01*
