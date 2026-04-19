# Phase 15: Cloud Settings UI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 15-cloud-settings-ui
**Areas discussed:** Размещение UI, Credentials UX + статус подключения, Privacy consent, Disabled state и ошибки

---

## Gray areas selection

| Option | Description | Selected |
|--------|-------------|----------|
| Место для Cloud-настроек | Отдельная секция vs встроенный блок vs disclosure в ProductModeCard | ✓ |
| Credentials UX + статус подключения | SecureField, save-flow, что такое «connected» | ✓ |
| Privacy consent | Modal sheet vs inline checkbox vs banner; persistence; отказ | ✓ |
| Cloud disabled state и ошибки | Disabled picker-сегмент, error placement, русские формулировки | ✓ |

**User's choice:** все (все 4 области).

---

## Область 1: Место для Cloud-настроек

### Q1 · Где должен жить блок с полями clientId/clientSecret, индикатором статуса и privacy consent?

Mockup сгенерирован: `docs/superpowers/specs/2026-04-20-phase-15-cloud-settings-placement.html` (три варианта рядом в стиле дизайн-системы v2).

| Option | Description | Selected |
|--------|-------------|----------|
| A · Отдельная секция «Облако» в сайдбаре | Новый SettingsSection.cloud + CloudSettingsView.swift, паттерн как TextStyle. Изолирует сложность, место для будущего (квоты/логи). +1 иконка в sidebar. | |
| B · Встроенный блок в «Общих» под ProductModeCard | Раскрывается при productMode == .cloud. Credentials рядом с picker, но GeneralSettingsContent утяжеляется; нет места ввести заранее. | |
| C · Disclosure внутри ProductModeCard | Паттерн Super's downloadStatusView. Консистентно, но карточка разбухает, consent-баннеру мало места. | ✓ |

**User's choice:** C · Disclosure внутри ProductModeCard.
**Notes:** Выбрано ради консистентности с Super (downloadStatusView). Минус — место под consent — решили через сжатый persistent banner в disclosure (см. Область 3).

### Q2 · Когда disclosure (поля + статус + consent) появляется под picker'ом?

| Option | Description | Selected |
|--------|-------------|----------|
| Когда productMode == .cloud (как Super) | Полная симметрия. Нужен временный клик на disabled Cloud-сегмент. | |
| Когда .cloud выбран ИЛИ ключи отсутствуют | Disclosure раскрывается по клику на Cloud-сегмент (даже disabled), setup-mode без switch; auto-switch после успешной проверки. | ✓ |
| Всегда видим, пока нет ключей | Call-to-action блок. Аггрессивно. | |

**User's choice:** Disclosure по клику на Cloud-сегмент (setup-mode) + когда .cloud выбран.
**Notes:** Решает chicken-egg — можно ввести ключи не переключаясь в Cloud.

---

## Область 2: Credentials UX + статус подключения

### Q1 · Как работают поля ввода Client ID / Secret?

| Option | Description | Selected |
|--------|-------------|----------|
| SecureField + кнопка «Сохранить» (Recommended) | Маскированные поля, Save активна когда оба непустые, сразу запускает проверку. | ✓ |
| SecureField + auto-save по blur | Живее, но рискованно (частичная пара, ранний test). | |
| Обычные TextField + Save | Видимые ключи — shoulder surfing risk. | |

**User's choice:** SecureField + кнопка «Сохранить».

### Q2 · Что значит «Подключено» и как тестируем?

| Option | Description | Selected |
|--------|-------------|----------|
| OAuth токен получен (Recommended) | `SberAuthService.getAccessToken()` успех. Быстро, не тратит токены GigaChat. | ✓ |
| Полный chat/completions ping | Гарантирует доступ к модели, но тратит токены и медленнее. | |
| Только «Проверить», без auto-test | Save → status «не проверено»; ручной клик. | |

**User's choice:** OAuth fetchToken success = «Подключено».
**Notes:** В процессе правок: имя функции исправлено с вымышленного `fetchToken()` на реальный `AuthService.getAccessToken() async throws -> String`.

### Q3 · Удаление ключей — как?

| Option | Description | Selected |
|--------|-------------|----------|
| «Очистить» + NSAlert-подтверждение (Recommended) | Destructive alert, две кнопки. Защищает от случайных кликов. | ✓ |
| «Очистить» без подтверждения | Быстро, но легко сломать конфигурацию. | |
| Без кнопки — стереть поля и Save | Неочевидно. | |

**User's choice:** «Очистить» + NSAlert.

---

## Область 3: Privacy consent

### Q1 · Формат privacy consent при первом включении Cloud?

| Option | Description | Selected |
|--------|-------------|----------|
| Modal sheet (Recommended) | Sheet при успешной проверке + первом переходе на Cloud. Две кнопки «Принять/Отмена». | |
| Inline-чекбокс в ProductModeCard | «[ ] Я понимаю...» перед активацией. Менее формально. | |
| Consent-банner в disclosure | Persistent блок с текстом + датой + «Отозвать». Не modal. | ✓ |

**User's choice:** Consent-банер в disclosure (persistent, не modal).
**Notes:** Pre-ack state (до acceptance): banner показывает текст + primary-кнопку «Принять и включить Cloud»; post-ack: дата + «Отозвать согласие». Cloud не активируется до ack.

### Q2 · Persistence: как часто показывать согласие?

| Option | Description | Selected |
|--------|-------------|----------|
| One-time ack, flag в UserDefaults (Recommended) | `cloudConsentAcceptedAt: Date?` в SettingsStore. | ✓ |
| Каждый enable Cloud | Каждое переключение — новый ack. Раздражает. | |
| One-time + перезапрос через 90 дней | Compliance-friendly, но сложнее. Избыточно для v2.0. | |

**User's choice:** One-time ack via UserDefaults flag.

### Q3 · Что происходит при отказе («Отмена»)?

| Option | Description | Selected |
|--------|-------------|----------|
| Остаться в предыдущем режиме (Recommended) | Picker возвращается на прежний выбор, ключи в Keychain сохраняются. | ✓ |
| Удалить ключи и остаться в standard | Агрессивно. | |
| Остаться на Cloud-вкладке, но режим не применить | Запутанно. | |

**User's choice:** Остаться в предыдущем режиме, ключи сохраняются.

---

## Область 4: Cloud disabled state и ошибки

### Q1 · Как выглядит Cloud-сегмент picker когда нет ключей?

| Option | Description | Selected |
|--------|-------------|----------|
| Grayed text + lock-icon (Recommended) | Осланный текст + lock.fill. Остаётся кликабельным — клик раскрывает setup-disclosure. | ✓ |
| Grayed и полностью disabled | .disabled(true) + отдельная кнопка-ссылка «Настроить Cloud». | |
| Скрыт пока нет ключей | Только Standard + Super в picker + кнопка «+ Добавить Cloud». | |

**User's choice:** Grayed + lock-icon, остаётся кликабельным.
**Notes:** В Codex round 1 обнаружено — current picker `.pickerStyle(.menu)` не поддерживает per-item clickable disabled. Решение в D-02 переписано на onChange-revert + showCloudSetup flag (тот же паттерн что уже используется для Super).

### Q2 · Где показывать ERROR при проверке или runtime cloud-запросе?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline status line в disclosure (Recommended) | Ember-точка + текст. Runtime-ошибки — дополнительно в BottomBar. | ✓ |
| NSAlert popup | Прерывает flow, плохо для runtime. | |
| Только в BottomBar | Непонятно в settings-контексте. | |

**User's choice:** Inline status line в disclosure.
**Notes:** Маппинг ошибок → строк живёт в View-слое (`errorMessage(for:)` в `CloudSettingsDisclosure`), **не** в `Core/ErrorMessages.swift` — сохраняет pure-UI boundary фазы.

### Q3 · Формулировки actionable-ошибок на русском?

| Option | Description | Selected |
|--------|-------------|----------|
| Claude предложит набор, уточнишь на execute (Recommended) | Draft в CONTEXT.md для 6 типов, правки на execute. | ✓ |
| Переиспользовать ErrorMessages.swift | Добавить cloud-кейсы туда. | |
| Обсудим сейчас подробно | Каждую формулировку проговорить отдельно. | |

**User's choice:** Claude предложит draft, уточнение на execute.
**Notes:** В Codex round 1 обнаружено — `AuthError` enum имеет 4 кейса, транспортные ошибки схлопываются в `networkError(String)`. D-11 переписан: маппинг через `URLError.code` инспекцию в View, generic-fallback для неразличимых кейсов. D-11.1 документирует out-of-scope кейсы (`tokenParsingFailed`, `CloudLLMClient.parsingFailed`, mid-session 401, quota).

---

## Claude's Discretion

Вошло в `<decisions>` CONTEXT.md:
- Файловое деление `CloudSettingsDisclosure` (отдельный файл рекомендован, планер решает).
- Точная вёрстка SecureField.
- Placement `lock.fill` иконки.
- Анимация раскрытия disclosure.
- Wording кнопок («Проверить» vs «Проверить подключение», «Очистить» vs «Удалить ключи»).
- Keyboard shortcut для Save.
- Ключ UserDefaults (`govorun.cloud.consent.acceptedAt` — предложение).
- Реализация `errorMessage(for: Error) -> String` в View (inline switch vs struct/enum).
- Извлечение `URLError.code` из `AuthError.networkError(String)`.

## Deferred Ideas

Вошло в `<deferred>` CONTEXT.md:
- Логи cloud-запросов в истории.
- Баланс токенов GigaChat.
- Auto-fallback cloud → super при потере сети (per REQUIREMENTS §Out of Scope).
- Multiple credential profiles.
- Cloud-specific text style settings.
- Export/import credentials.
- Pre-ack state отдельный mockup — домоделировать при планировании.

---

## Codex review (round 1)

Верификация CONTEXT.md против кода. Все 7 findings подтверждены и приняты, патчи применены:

1. **[Blocking] D-02/D-09 clickable-disabled Picker** → onChange-revert + showCloudSetup flag (no custom control).
2. **[Blocking] D-07 revoke race** → D-07.1 accept-risk для v2.0 с явным обоснованием.
3. **[High] D-04/D-11 OAuth specificity** → D-11 переписан вокруг реальных AuthError кейсов + URLError инспекция в View.
4. **[High] Pure-UI противоречие** → D-10 маппинг в View, Core/ErrorMessages.swift не трогаем.
5. **[Medium] D-11 не покрывает все кейсы** → D-11.1 out-of-scope secttion для `tokenParsingFailed` etc.
6. **[Low] Имя метода** → `fetchToken()` → `getAccessToken() async throws -> String`.
7. **[Low] Crowded SettingsView.swift** → Discretion: рекомендация планеру выделить `CloudSettingsDisclosure.swift`.

Round 2 не понадобился — после round 1 патчей пользователь вырубил автоматические Codex-ревью, плагин остался для ручного вызова.
