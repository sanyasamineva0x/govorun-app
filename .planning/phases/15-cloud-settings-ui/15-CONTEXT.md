# Phase 15: Cloud Settings UI - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Настройки для Говорун Cloud в существующем окне Settings. Пользователь вводит clientId/clientSecret (сохраняются в Keychain через `CredentialStoring`), даёт privacy consent перед тем как аудио и текст уйдут в Сбер, видит статус подключения (OAuth token fetch) и выбирает Cloud как третий ProductMode в picker. Сам cloud-пайплайн (аудио-in, нормализация) — готов из Phase 12-14; эта фаза только UI-оболочка для его настройки и активации.

</domain>

<decisions>
## Implementation Decisions

### Размещение UI
- **D-01:** Cloud-настройки живут внутри `ProductModeCard` как disclosure-блок — паттерн как Super's `downloadStatusView`. Без новой секции в sidebar; без изменений в `SettingsSection` enum. Файловое деление — на усмотрение планера (см. Claude's Discretion): `SettingsView.swift` уже 26KB + `ProductModeCard` ~240 строк, планер может выделить `CloudSettingsDisclosure` в отдельный файл или оставить private subview в том же файле.
- **D-02:** Текущий `Picker(...).pickerStyle(.menu)` в `ProductModeCard` (строки 511-522) не поддерживает «кликнуть disabled-item без мутации selection». Поэтому взаимодействие — через **onChange-guard + revert + setup-flag**, тот же паттерн что уже используется для Super (строки 519-521):
  1. Picker остаётся `.menu`-style, не переписываем на custom segmented control.
  2. Новый `@State var showCloudSetup: Bool` в `ProductModeCard`.
  3. `.onChange(of: selection)` при выборе `.cloud`: если нет ключей/консента — revert `selection` на предыдущее значение + `showCloudSetup = true`.
  4. Disclosure под HStack'ом рендерится когда `productMode == .cloud` ИЛИ `showCloudSetup == true`.
  5. После успешной проверки OAuth + acceptance consent-баннера — код явно пишет `selection = .cloud` (обычный flow onChange разрешит switch, так как все prerequisites есть).
  Это сохраняет стандартный `.menu`-picker и не требует кастомного контрола.

### Credentials UX
- **D-03:** Два `SecureField` для Client ID и Client Secret. Явная primary-кнопка «Сохранить» активна когда оба поля непустые. Save пишет в `CredentialStore` (уже готов) и сразу запускает OAuth-проверку (см. D-04). Без auto-save по blur.
- **D-04:** «Подключено» = успешный вызов `AuthService.getAccessToken() async throws -> String` (реализует `SberAuthService` actor). Не делаем полный `/chat/completions` ping — не тратим токены GigaChat. Auto-test после Save + secondary-кнопка «Проверить» для manual retest. Возвращаемое `throws` маппится в UI-статус: `success → «Подключено»`, `AuthError → error inline` (см. D-11 для маппинга).
- **D-05:** Удаление ключей — secondary-кнопка «Очистить» + NSAlert-подтверждение с текстом вида «Удалить ключи API? Cloud-режим станет недоступен.» Две кнопки: «Удалить» (destructive) / «Отмена».

### Privacy Consent
- **D-06:** Consent — persistent banner внутри disclosure, не modal sheet. Два состояния: **pre-ack** («Аудио и текст отправляются в Сбер GigaChat» + primary-кнопка «Принять и включить Cloud») и **post-ack** («Активно с YYYY-MM-DD» + secondary «Отозвать согласие»). Cloud-режим НЕ активируется пока pre-ack не подтверждён.
- **D-07:** One-time acceptance. Поле `cloudConsentAcceptedAt: Date?` в `SettingsStore` (UserDefaults, ключ `govorun.cloud.consent.acceptedAt`). Revoke: удаляет flag → `productMode = .standard` → disclosure возвращается в pre-ack. Ключи в Keychain остаются (пользователь может передумать).
- **D-07.1 (revoke-during-dictation race, accept-risk):** `AppState.applyProductMode(.standard)` откладывает switch до возврата сессии в idle (existing pattern for non-disruptive mode changes); `PipelineEngine.stopRecording` снапшотит `productMode` и `cloudClient` в начале обработки. Если пользователь revoke-ает consent во время активной диктовки, текущий cloud-запрос может дослаться на сервера Сбера ДО применения revoke. Для v2.0 **принимаем риск**: revoke вступает в силу со следующей сессии, одна последняя передача после revoke допустима. Обоснование: (a) звуки сессии уже захвачены и в пути — отменить их не получится без обрыва UX, (b) добавление «immediate cancel cloud task» требует изменений в `PipelineEngine` и `CloudLLMClient` (out of scope для pure-UI фазы), (c) private кейс — пользователь на середине диктовки редко отзывает consent. Планер должен документировать это в UAT/release notes.
- **D-08:** При отказе (пользователь не нажал «Принять и включить Cloud» и ушёл из настроек или переключил picker обратно) productMode остаётся как был до попытки; ключи сохраняются в Keychain если были введены и сохранены.

### Disabled State и Ошибки
- **D-09:** Cloud-сегмент picker'а когда `!cloudAvailable` — grayed text (Ink opacity 0.25) + `lock.fill` icon справа от текста, **но остаётся кликабельным**: по клику раскрывается setup-disclosure (D-02). SwiftUI: не используем `.disabled(true)`, а кастомный state.
- **D-10:** Runtime/save errors показываются inline в status-line disclosure (Ember-точка + конкретный текст). **Маппинг `AuthError`/`LLMError → локализованная строка` живёт в View-слое** (например, приватный `func errorMessage(for: Error) -> String` внутри `CloudSettingsDisclosure`), **не в `Core/ErrorMessages.swift`** — сохраняем pure-UI boundary фазы. Runtime-ошибки во время диктовки в Cloud-режиме — отдельный вопрос: BottomBar уже использует `Core/ErrorMessages.swift` для локальных ошибок; добавление там cloud-кейсов — **опционально и не в scope Phase 15**; можно отложить до Phase 17 (Polish & Rollout) или сделать inline в AppState без правки Core.
- **D-11:** Error messages (draft, финальные формулировки — на execute-фазе). **Ограничение `AuthError`**: enum имеет 4 кейса (`credentialsNotFound`, `networkError(String)`, `invalidResponse(statusCode:)`, `tokenParsingFailed`). Транспортные ошибки (offline / DNS / TLS / timeout) схлопываются в `networkError(String)` — различать их можно только инспекцией `URLError.code` из `errorMessage(for:)`. Для v2.0 принимаем более грубый маппинг:
  - **`AuthError.credentialsNotFound`:** «Введите ключи API. Без них Cloud недоступен.»
  - **`AuthError.invalidResponse(401)`:** «Ключи отклонены Сбером. Проверьте Client ID и Secret.»
  - **`AuthError.invalidResponse(429)`:** «Слишком много запросов. Попробуйте через минуту.»
  - **`AuthError.invalidResponse(500...599)`:** «Ошибка на стороне Сбера. Попробуйте позже.»
  - **`AuthError.invalidResponse(other)` + `AuthError.tokenParsingFailed`:** «Сбой Cloud. Попробуйте позже.» (generic fallback — различать в UI не имеет смысла без Services изменений)
  - **`AuthError.networkError(String)`** — маппинг через `URLError.code` (если удалось извлечь; fallback на generic если нет):
    - `.notConnectedToInternet`, `.networkConnectionLost` → «Нет интернета. Cloud временно недоступен.»
    - `.timedOut` → «Сбер не ответил за 30 секунд. Проверьте сеть.»
    - прочие (DNS/TLS/etc) → «Сервис Сбера недоступен. Попробуйте позже.»
  - **`AuthError.invalidResponse(-1)` (не HTTP response):** generic fallback «Сбой Cloud. Попробуйте позже.»
- **D-11.1 (out-of-scope ошибки):** Следующие кейсы существуют в коде (`CloudLLMClient.parsingFailed`, mid-session token-expiry 401, quota/permission exhaustion отличная от 429), но **маппятся в generic «Сбой Cloud» без дифференциации**. Дифференциация требует расширения `AuthError` / `LLMError` (Services-слой) — out of scope для Phase 15 (pure UI). Этот пункт — явный нон-гол, не забыть упомянуть в UAT.
- **D-11.2 (ОВЕРРАЙД D-11.1 для URLError, принят 2026-04-20):** 15-RESEARCH.md Landmine #3 показал: `SberAuthService.swift:98` заворачивает `URLError` в `String` через `.localizedDescription`, поэтому `if let urlErr = error as? URLError` во View никогда не срабатывает — UI-SPEC §Status table для `AuthError.networkError(URLError.notConnectedToInternet / .timedOut / other)` был аспирационным. Пользователь выбрал **Path B: сохраняем гранулярный UX**. Действия:
  1. Расширить `AuthError.networkError` в `Govorun/Services/SberAuthService.swift` — нести `URLError?` рядом с `description` (`.networkError(urlError: URLError?, description: String)`).
  2. Обновить `Equatable` conformance `AuthError` чтобы сравнивать оба поля (для тестов).
  3. Обновить одну точку вызова в `CloudLLMClient.swift` если она явно матчит на `.networkError(let msg)` — заменить паттерн на `.networkError(_, let msg)` или `.networkError(let urlErr, let msg)`.
  4. `errorMessage(for:)` во View матчит на `.networkError(let urlErr, _)` и разворачивает `urlErr?.code` в специфичные сообщения согласно UI-SPEC §Status table.
  5. Границу фазы слегка размыкаем (Services/ получает ~10 строк), но всё в одной TDD-итерации (тест → код → рефактор). Остальные D-11.1 кейсы (`parsingFailed`, token-expiry) остаются generic — это точечный оверрайд только для URLError.

### Claude's Discretion
- **Файловое деление:** планер сам решает — `CloudSettingsDisclosure` приватный subview в `SettingsView.swift` или отдельный `CloudSettingsDisclosure.swift` (рекомендация: отдельный файл, т.к. `SettingsView.swift` уже 26KB + `ProductModeCard` 240 строк, а новая логика принесёт ещё ~200+ строк). В любом случае `ProductModeCard` остаётся тем же struct'ом, disclosure — новый subview.
- Точная вёрстка `SecureField` (spacing, bordered vs plain) — следовать дизайн-системе v2 (Mist border 1px, border-radius 8pt).
- Placement `lock.fill` icon в disabled Cloud-сегменте (до/после текста).
- Анимация раскрытия/скрытия disclosure (`easeOut` 0.2-0.25s — как существующие `.animation(.easeOut)`).
- Wording кнопок уточнить: «Проверить» vs «Проверить подключение»; «Очистить» vs «Удалить ключи».
- Keyboard shortcut для Save (⌘S или ничего).
- Конкретный ключ UserDefaults (`govorun.cloud.consent.acceptedAt` — предложение; соответствует существующему naming в `SettingsStore.Keys`).
- Реализация `errorMessage(for: Error) -> String` в View — inline switch или отдельная `CloudErrorCopy` struct/enum (не в `Core/`).
- Извлечение `URLError.code` из `AuthError.networkError(String)` — либо обогатить AuthError в будущем (вне scope), либо парсить `URLError` напрямую в View. Планер выбирает.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning или implementing.**

### Requirements & Roadmap
- `.planning/REQUIREMENTS.md` — UI-01 (поля clientId/secret), UI-02 (индикатор статуса), UI-03 (picker с тремя вариантами), UI-04 (privacy consent на первом enable)
- `.planning/ROADMAP.md` §Phase 15 — Goal, Depends on Phase 13, Success Criteria 1-4

### Phase 13 — Mode & Routing (предыдущая фаза, foundation)
- `.planning/phases/13-mode-routing/13-CONTEXT.md` §D-07 (guard в `applyProductMode(.cloud)` + `cloudAvailable`), §D-08 (пользователь вводит ключи через UI Phase 15, save через CredentialStore)

### Существующий код — что трогаем
- `Govorun/Views/SettingsView.swift` §`ProductModeCard` (строка 291+) — контейнер, расширяется disclosure-блоком для Cloud. Референс: `downloadStatusView` для Super (строки ~525-540).
- `Govorun/Models/ProductMode.swift` — enum готов: `.standard / .superMode / .cloud` с `title`, `subtitle`, `usesLLM`, `usesLocalLLM`, `isCloud`. **Не меняется.**
- `Govorun/App/AppState.swift` — `@Published var cloudAvailable: Bool` (строки 40, 242, 307), `applyProductMode(.cloud)` (~строка 720+). Binding для disabled-state picker.
- `Govorun/Storage/CredentialStore.swift` — `CredentialStoring` protocol (`save/get/delete`) полностью готов. **Не меняется.**
- `Govorun/Storage/SettingsStore.swift` — добавить `cloudConsentAcceptedAt: Date?` + ключ в `Keys` enum + `registerDefaults()` + accessor.
- `Govorun/Services/SberAuthService.swift` — `AuthService.getAccessToken() async throws -> String` для D-04 проверки подключения (bросает `AuthError`). **Не меняется.**
- `Govorun/Core/ErrorMessages.swift` — референс паттерна локализованных русских строк (не правим — см. D-10).

### Design system
- `docs/superpowers/specs/2026-04-10-design-system-v2-design.md` — палитра (Snow/Mist/Ink/Sage/Ember), Source Serif 4 для заголовков, SF Pro для body, StatusCard→StatusDot, BrandedButton, SettingsToggleRow, border-radius 14pt/8pt
- `docs/superpowers/specs/2026-04-20-phase-15-cloud-settings-placement.html` — mockup из discuss-phase, selected Option C (disclosure в ProductModeCard). Pre-ack state нужно домоделировать.

### Референс-фаза для UI pattern
- Phase 8-ui (TextStyleSettingsView.swift) — пример отдельной секции sidebar с карточками, animation, EnvironmentObject binding (не повторяем напрямую — мы выбрали disclosure, но tone-of-voice и spacing оттуда)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **ProductModeCard** (`SettingsView.swift:291`) — существующий контейнер, уже имеет паттерн disclosure для Super's `downloadStatusView`. Cloud disclosure строится по аналогии рядом с существующим `if productMode == .superMode { downloadStatusView }`.
- **CredentialStoring** (`Storage/CredentialStore.swift`) — `save/get/delete` + `MockCredentialStore` для тестов. SecureField binds через простой `@State` + явный save в обработчике кнопки.
- **AppState.cloudAvailable @Published** (`App/AppState.swift:40`) — уже обновляется в init и после save. Binding для disabled Cloud-сегмента и для условного рендера disclosure.
- **SberAuthService.getAccessToken()** (actor, реализует `AuthService` protocol) — готовый endpoint для D-04 проверки. Actor-based, coalesced через `inFlightTask`, `async throws -> String` (бросает `AuthError`: `credentialsNotFound / networkError(String) / invalidResponse(statusCode:) / tokenParsingFailed`).
- **ErrorMessages.swift** — паттерн локализованных русских строк с LocalizedError. Можно extend или inline.
- **Design system v2 tokens** — готовы в `SettingsTheme.swift` (после design-system-v2 миграции): Snow/Mist/Ink/Sage/Ember + Source Serif 4.

### Established Patterns
- **Disclosure в ProductModeCard** — готовый прецедент для productMode-dependent UI (Super's downloadStatusView). Cloud идёт тем же путём.
- **@MainActor View + @EnvironmentObject AppState** — стандарт, используется во всех Views/.
- **SettingsStore миграции** — `migrate*()` методы в `init` для новых ключей; `registerDefaults()` для дефолтов; private enum Keys.
- **NSAlert confirmation** — паттерн для destructive actions (пример: удаление snippet). Использовать для D-05.
- **SwiftFormat + strict concurrency** — все Views соответствуют `SWIFT_STRICT_CONCURRENCY: complete`.
- **TDD: моки через протоколы** — уже готовый `MockCredentialStore`; для `SberAuthService` есть mock через `AuthService` protocol.

### Integration Points
- **ProductModeCard** — точка расширения: добавляется cloud-disclosure рядом с super-disclosure. Высота карточки растёт только когда Cloud активен/настраивается.
- **AppState.applyProductMode(.cloud)** — проверяет `cloudConsentAcceptedAt != nil` + `cloudAvailable` + свежий OAuth token перед switch. Guard из Phase 13 D-07 расширяется consent-check'ом.
- **SettingsStore** — новое поле `cloudConsentAcceptedAt: Date?` + revoke метод `clearCloudConsent()` (устанавливает nil).
- **ErrorMessages.swift не трогаем** — маппинг ошибок живёт в View-слое (D-10).
- **Нет изменений в**: `Core/` (включая `ErrorMessages.swift`), `Services/`, `Models/ProductMode.swift`, `CredentialStore.swift`, `PipelineEngine.swift`, `SberAuthService.swift`, `CloudLLMClient.swift`. Это чисто UI-фаза.

</code_context>

<specifics>
## Specific Ideas

- Выбранный паттерн — Option C из mockup (`docs/superpowers/specs/2026-04-20-phase-15-cloud-settings-placement.html`). Pre-ack state не нарисован в текущем mockup — при планировании домоделировать рендер состояния «ключи сохранены, OAuth ok, consent не дан».
- Палитра строго v2: Sage для connected-статуса, Ember для error-статуса, Ink для primary-кнопок («Сохранить», «Принять и включить Cloud»), Mist для borders/дивайдеров между Credentials / Consent sub-блоками внутри disclosure.
- Tone of voice: короткие русские фразы в императиве («Введите», «Проверьте», «Попробуйте позже»). Без инфинитивов-указаний типа «Необходимо ввести». Без «пожалуйста».
- «Говорун Cloud» title + «Голосовой ввод через GigaChat Max» subtitle — уже в `ProductMode.swift`, не менять.
- Clickable disabled-state Cloud-сегмента — нестандартно для SwiftUI Picker'а. Возможно нужен кастомный HStack с segmented-look вместо стандартного `Picker`. При планировании проверить: текущая реализация уже кастомная (см. `ProductModeCard` код) — но SegmentPicker-like. Cloud-сегмент должен visually отличаться + быть кликабельным но не устанавливать selection.
- Дата consent format: `Date` в Keychain не храним, в UserDefaults стандартный `Date`. Формат отображения — относительный («сегодня», «3 дня назад») или абсолютный (`DateFormatter.short`) — на усмотрение (Discretion).

</specifics>

<deferred>
## Deferred Ideas

- Логи cloud-запросов в истории/settings — v3 или after-launch
- Баланс токенов GigaChat в settings (token usage display) — post-launch per REQUIREMENTS §Future
- Auto-fallback cloud → super при потере сети — per REQUIREMENTS §Out of Scope (UX risk, отложено)
- Multiple credential profiles (работа + личное) — post-launch
- Cloud-specific text style settings (другие температуры/модели) — v3
- Export/import credentials — не нужно, ключи выдаются в ЛК Сбера по запросу
- Pre-ack state отдельного mockup — при планировании домоделировать (specifics)

</deferred>

---

*Phase: 15-cloud-settings-ui*
*Context gathered: 2026-04-20*
