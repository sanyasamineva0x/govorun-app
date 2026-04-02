# Phase 8: UI - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Вкладка "Стиль текста" в окне настроек — авто/ручной режим с визуальным feedback. Пользователь может видеть и переключать стили SuperTextStyle в SettingsView.

</domain>

<decisions>
## Implementation Decisions

### Размещение UI
- **D-01:** Вкладка "Стиль текста" — новая секция в `SettingsView` (сайдбар + контент), НЕ в NSMenu/StatusBarController. Новый case в `SettingsSection`.
- **D-02:** Вкладка всегда видна в сайдбаре. Без модели — disabled контент с overlay поверх карточек.

### Layout карточек стилей
- **D-03:** Ручной режим — три вертикальных карточки (relaxed/normal/formal) на полную ширину, друг под другом. Чекмарк на выбранном стиле. Каждая карточка с кратким описанием.

### Состояние "без модели"
- **D-04:** Карточки стилей видны но disabled (серые/размытые). Overlay с пояснением "Для стилей нужна ИИ-модель" и кнопкой перехода к скачиванию. Не NSAlert.

### Авто-режим отображение
- **D-05:** Статический текст "Стиль определяется автоматически по приложению". Без live-обновления текущего стиля (окно настроек = Говорун — активное приложение).

### Claude's Discretion
- Иконка и title для секции в сайдбаре
- Точный текст описаний на карточках стилей (relaxed/normal/formal)
- Визуальный стиль disabled overlay (blur, opacity, цвета)
- Анимации переключения авто/ручной
- Структура SwiftUI View (один файл или split)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей — секция UI
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — секция UI: "Стиль текста", вкладка, сегмент авто/ручной, карточки, состояние без модели

### Существующий UI (паттерны для следования)
- `Govorun/Views/SettingsView.swift` — главный экран настроек: сайдбар + контент, `GeneralSettingsContent`, `ProductModeCard`
- `Govorun/Views/SettingsTheme.swift` — `SettingsSection` enum, `visibleCases`, UI-компоненты: `settingsCard()`, `BrandedEmptyState`, `SectionHeader`, `SettingsToggleRow`, `StaggeredAppear`
- `Govorun/Views/AppModeSettingsView.swift` — текущая вкладка режимов (удаляется в Phase 9), паттерн работы с overrides

### Данные (Phase 6, готовы)
- `Govorun/Services/SettingsStore.swift` — `superStyleMode: SuperStyleMode` (.auto/.manual), `manualSuperStyle: SuperTextStyle` (.normal default)
- `Govorun/Models/SuperTextStyle.swift` — enum relaxed/normal/formal, displayName, styleBlock, systemPrompt

### Состояние модели
- `Govorun/App/AppState.swift` — `superAssetsState`, `superModelDownloadState`, `effectiveProductMode` — для определения доступности Super

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `settingsCard()` modifier — стандартная карточка настроек (padding + ultraThinMaterial + rounded corners)
- `BrandedEmptyState` — пустое состояние с иконкой и кнопкой (можно использовать как fallback)
- `SectionHeader` — заголовок секции с иконкой
- `SettingsToggleRow` — строка с toggle (для переключения авто/ручной не подходит, но паттерн)
- `StaggeredAppear` — анимация появления элементов
- `ProductModeCard` — паттерн карточки с Picker .segmented и зависимым контентом ниже
- Фирменные цвета: `Color.cottonCandy` (акцент), `Color.oceanMist` (success), `Color.alabasterGrey` (нейтральный)

### Established Patterns
- SettingsView использует `@EnvironmentObject private var appState: AppState` для доступа к данным
- Settings binding через `settingsBinding(\.keyPath)` в GeneralSettingsContent
- `SettingsSection` enum с `visibleCases` контролирует что видно в сайдбаре
- AppState.superAssetsState определяет доступность Super-режима

### Integration Points
- `SettingsSection` — добавить новый case, обновить `visibleCases`
- `SettingsView.body` — добавить case в switch для нового контента
- `SettingsStore` — superStyleMode и manualSuperStyle уже готовы (Phase 6)
- `AppState` — superAssetsState для проверки доступности модели

</code_context>

<specifics>
## Specific Ideas

- Карточки вертикально, не горизонтально — пользователь хочет больше места под описания
- Disabled overlay вместо empty state — пользователь видит что его ждёт после скачивания модели

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-ui*
*Context gathered: 2026-04-01*
