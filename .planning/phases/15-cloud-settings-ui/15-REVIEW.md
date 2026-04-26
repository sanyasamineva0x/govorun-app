---
phase: 15-cloud-settings-ui
reviewed: 2026-04-20T21:35:59Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - Govorun/Storage/SettingsStore.swift
  - Govorun/Services/SberAuthService.swift
  - Govorun/Services/CloudLLMClient.swift
  - Govorun/Views/CloudErrorCopy.swift
  - Govorun/App/AppState.swift
  - Govorun/Views/SettingsTheme.swift
  - Govorun/Views/CloudSettingsDisclosure.swift
  - Govorun/Views/SettingsView.swift
findings:
  critical: 0
  high: 1
  medium: 2
  low: 1
  info: 3
  total: 7
status: fixed
fix_report: 15-REVIEW-FIX.md
fixed_at: 2026-04-22T20:06:30+03:00
---

# Phase 15: Cloud Settings UI — Code Review Report

> **Status: FIXED 2026-04-22.** H-01, M-01, M-02, L-01, I-02, I-03 закрыты; I-01 accepted-risk. См. [15-REVIEW-FIX.md](15-REVIEW-FIX.md).

**Проверено:** 2026-04-20T21:35:59Z
**Глубина:** standard
**Файлов:** 8 (7 по заданию + `SettingsTheme.swift` для StatusDot контекста)
**Статус:** issues-found

---

## Сводная таблица

| ID | Severity | Файл | Строка | Описание |
|----|----------|------|--------|----------|
| H-01 | High | `CloudLLMClient.swift` | 159, 230 | Force unwrap `URL(string:)!` в production |
| M-01 | Medium | `CloudSettingsDisclosure.swift` | 263 | StatusDot missing `accessibilityLabel` по UI-SPEC |
| M-02 | Medium | `CloudSettingsDisclosure.swift` | 518–526 | Cloud-сегмент Picker не имеет accessibility-метки «Cloud — требуется настройка» |
| L-01 | Low | `CloudSettingsDisclosure.swift` | 361 | Drift copy в `accessibilityHint` «Отозвать согласие» |
| I-01 | Info | `SberAuthService.swift` | 51–56 | `fatalError` в `static let defaultTokenURL` |
| I-02 | Info | `CloudSettingsDisclosure.swift` | 204–214, 219–229 | `await MainActor.run { }` избыточен внутри `Task {}` из `@MainActor` контекста |
| I-03 | Info | `CloudSettingsDisclosure.swift` | 337–342 | `DateFormatter` создаётся заново при каждом обновлении body |

---

## High Issues

### H-01: Force unwrap при построении URL в `CloudLLMClient`

**Файл:** `Govorun/Services/CloudLLMClient.swift:159` и `:230`

**Проблема:**
```swift
// Строка 159
var request = URLRequest(url: URL(string: configuration.baseURLString + "/files")!)
// Строка 230
var request = URLRequest(url: URL(string: configuration.baseURLString + "/chat/completions")!)
```

`configuration.baseURLString` — пользовательский параметр типа `String`. Если строка невалидна (пробел, некорректный символ, пустота), `URL(string:)` вернёт `nil`, и force unwrap упадёт с `EXC_BAD_INSTRUCTION`, убив процесс приложения. CLAUDE.md §Error Handling явно запрещает `!` в production коде.

В runtime `defaultBaseURLString` корректен, но `CloudLLMConfiguration` принимает `baseURLString` снаружи и не валидирует его в `init`. Падение возможно при тестировании с кастомным endpoint или при будущей пользовательской настройке URL.

**Исправление:**
```swift
// Заменить на guard let + mapped error

private func uploadAudio(_ audioData: Data, token: String) async throws -> String {
    guard let baseURL = URL(string: configuration.baseURLString) else {
        throw LLMError.networkError("Некорректный Cloud URL: \(configuration.baseURLString)")
    }
    var request = URLRequest(url: baseURL.appending(path: "files"))
    // ...
}

private func sendChatCompletion(...) async throws -> String {
    guard let baseURL = URL(string: configuration.baseURLString) else {
        throw LLMError.networkError("Некорректный Cloud URL: \(configuration.baseURLString)")
    }
    var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
    // ...
}
```

---

## Medium Issues

### M-01: `CloudStatusBlock` — отсутствует `accessibilityLabel` на контейнере

**Файл:** `Govorun/Views/CloudSettingsDisclosure.swift:249–265`

**Проблема:**
Согласно UI-SPEC §Accessibility, `StatusDot` (в виде HStack) должен читаться как `«Статус подключения: {title}»` через `.accessibilityElement(children: .combine)`. Сейчас код имеет `.accessibilityElement(children: .combine)` на внешнем HStack, но без `.accessibilityLabel(...)`. VoiceOver скомбинирует дочерние элементы — кружок (без label) + текст — и прочитает только текст статуса, теряя контекст «Статус подключения».

```swift
// Текущий код (строки 249–265):
HStack(spacing: 0) {
    switch connectionState { ... }
    Spacer()
}
.accessibilityElement(children: .combine)
// ↑ нет .accessibilityLabel → VoiceOver читает «Не настроено» без контекста
```

**Исправление:**
```swift
HStack(spacing: 0) {
    switch connectionState {
    case .notConfigured:
        StatusDot(title: "Не настроено", state: .idle)
    case .checking:
        StatusDot(title: "Проверяю подключение…", state: .idle)
    case .connected:
        StatusDot(title: "Подключено", state: .connected)
    case .error(let message):
        StatusDot(title: message, state: .error)
    }
    Spacer()
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Статус подключения: \(statusTitle)")
```

Где `statusTitle` — вычислимое свойство, возвращающее строку статуса (та же, что передаётся в `StatusDot`).

---

### M-02: Cloud-сегмент Picker не имеет accessibility-метки по UI-SPEC

**Файл:** `Govorun/Views/SettingsView.swift:517–528`

**Проблема:**
UI-SPEC §Accessibility, строка «Cloud segment when disabled-but-clickable»:
- `.accessibilityLabel` = «Cloud — требуется настройка»
- `.accessibilityHint` = «Нажмите, чтобы открыть настройки облачного режима»

В коде `HStack` с `Text(mode.title)` + `Image(systemName: "lock.fill")` внутри Picker не имеет ни `.accessibilityLabel`, ни `.accessibilityHint`. VoiceOver прочитает «Cloud, lock, пункт меню» — непонятно для пользователя с ограниченными возможностями.

```swift
// Текущий код (строки 518–524):
if mode == .cloud, !appState.cloudAvailable {
    HStack(spacing: 4) {
        Text(mode.title)
        Image(systemName: "lock.fill").font(.caption)
    }
    .foregroundStyle(Color.ink.opacity(0.25))
    .tag(mode)
    // ↑ нет accessibility-метки
}
```

**Исправление:**
```swift
if mode == .cloud, !appState.cloudAvailable {
    HStack(spacing: 4) {
        Text(mode.title)
        Image(systemName: "lock.fill").font(.caption)
    }
    .foregroundStyle(Color.ink.opacity(0.25))
    .tag(mode)
    .accessibilityLabel("Cloud — требуется настройка")
    .accessibilityHint("Нажмите, чтобы открыть настройки облачного режима")
}
```

---

## Low Issues

### L-01: Copy drift в `accessibilityHint` кнопки «Отозвать согласие»

**Файл:** `Govorun/Views/CloudSettingsDisclosure.swift:361`

**Проблема:**
UI-SPEC §Accessibility, locked copy для «Отозвать согласие»:
> «Отключает облачный режим. Ключи останутся сохранены.»

Код содержит:
```swift
.accessibilityHint("Отключает облачный режим со следующей сессии. Ключи останутся сохранены.")
```

Добавленная фраза «со следующей сессии» не согласована со spec. Она технически корректна (D-07.1 deferred-to-idle поведение), но нарушает §Copywriting Contract: «Strings below are locked — planner must use exactly these». Если отклонение обоснованно, оно должно быть зафиксировано в PATTERNS.md или CONTEXT.md как documented deviation.

**Исправление:**
```swift
.accessibilityHint("Отключает облачный режим. Ключи останутся сохранены.")
```

Либо внести явный комментарий в PATTERNS.md: «D-07.1: accessibility hint расширен — «со следующей сессии» отражает deferred-to-idle семантику».

---

## Info Items

### I-01: `fatalError` в `static let defaultTokenURL` (`SberAuthService`)

**Файл:** `Govorun/Services/SberAuthService.swift:51–56`

**Наблюдение:**
```swift
static let defaultTokenURL: URL = {
    guard let url = URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth") else {
        fatalError("Невалидный defaultTokenURL")
    }
    return url
}()
```

URL — compile-time литерал, так что `fatalError` на практике недостижим. Тем не менее, `fatalError` в production-коде — нежелательный паттерн в проекте, где конвенция строга (CLAUDE.md §Error Handling запрещает `!`, `fatalError` — смежный). Стандартный альтернативный паттерн для `static let URL`:

```swift
// Альтернатива — URL(string:) с литеральным URL всегда non-nil,
// можно использовать URL(string:)! только для compile-time констант,
// но лучше:
static let defaultTokenURL = URL(staticString: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")
// URL(staticString:) — @StaticString init, компилятор гарантирует non-nil
```

Если `URL(staticString:)` недоступен на целевом SDK, текущий вариант с `fatalError` приемлем как последнее средство.

---

### I-02: `await MainActor.run { }` избыточен в `Task {}` из `@MainActor`-изолированного View

**Файл:** `Govorun/Views/CloudSettingsDisclosure.swift:204–214` и `219–229`

**Наблюдение:**
```swift
// saveAndProbe() — вызывается из Button action в @MainActor View
Task {
    let result = await appState.probeCloudConnection()
    await MainActor.run {       // ← избыточно
        switch result { ... }   // connectionState — @State, уже на MainActor
    }
}
```

`Task {}`, созданный внутри метода `@MainActor`-изолированного `struct View`, наследует `@MainActor` изоляцию (Swift 5.10, SE-0338). Обновление `@State`/`@Binding` внутри такого Task'а уже выполняется на `MainActor`. Дополнительный `await MainActor.run { }` не несёт вреда, но создаёт ложное ощущение, что без него код небезопасен.

**Исправление (опционально):**
```swift
Task {
    let result = await appState.probeCloudConnection()
    switch result {
    case .success:
        connectionState = .connected
    case .failure(let authError):
        connectionState = .error(cloudErrorMessage(for: authError))
    }
}
```

---

### I-03: `DateFormatter` создаётся заново при каждом рендере `postAckContent`

**Файл:** `Govorun/Views/CloudSettingsDisclosure.swift:337–342`

**Наблюдение:**
```swift
@ViewBuilder
private func postAckContent(acceptedAt: Date) -> some View {
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
    // ...
}
```

`DateFormatter` — тяжёлый объект (парсинг locale, calendar). Он пересоздаётся при каждом обновлении SwiftUI `body`, что происходит при каждом `@State`/`@EnvironmentObject` изменении в родительских views. На практике это не критично (экран настроек не перерисовывается в цикле), но это паттерн, которого следует избегать.

**Исправление:** вынести в `static let` или `private let` на уровне структуры `CloudConsentBanner`:
```swift
private struct CloudConsentBanner: View {
    // ...
    private static let consentDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
    // ...
    @ViewBuilder
    private func postAckContent(acceptedAt: Date) -> some View {
        Text("Cloud активен с \(Self.consentDateFormatter.string(from: acceptedAt))")
        // ...
    }
}
```

---

## Проверка по приоритетным областям задания

### 1. Secret handling — CredentialStore / clientSecret / clientId

**PASS.** Ни `print`, ни `Logger`, ни `os_log` не содержат значений `clientId`, `clientSecret`, `accessToken`, `credential` в 7 проверяемых файлах. `CloudLLMClient.logger.info(...)` на строке 131 логирует только `retryDelay` (число), без токенов. `buildTokenRequest` пишет credentials в HTTP-заголовок без логирования — корректно.

### 2. Swift strict concurrency — `@MainActor` + `Task {}`

**PASS с оговоркой.** `AppState` корректно помечен `@MainActor`. Все три метода шима (`saveCloudCredentials`, `deleteCloudCredentials`, `probeCloudConnection`) неявно `@MainActor`-изолированы (наследуют от класса). `CloudSettingsDisclosure` и `ProductModeCard` — SwiftUI Views, изолированы на `MainActor` по умолчанию. `Task {}` в `saveAndProbe`/`probeOnly` наследуют `@MainActor`. Паттерн `await MainActor.run { }` внутри уже-MainActor Task'а избыточен но не опасен (I-02).

### 3. Нет force unwrap (`!`)

**FAIL — H-01.** `CloudLLMClient.swift` содержит два `!` при построении URL (строки 159, 230). Все остальные файлы из скоупа фазы 15 — без `!`.

### 4. Разделение слоёв — Views не импортируют Services/Storage напрямую

**PASS.** `CloudSettingsDisclosure.swift` и `CloudErrorCopy.swift` импортируют только `SwiftUI`/`Foundation`. Взаимодействие с `AppState` идёт через `@EnvironmentObject`. `cloudErrorMessage(for:)` принимает `Error` — работает с протоколом `AuthError` без прямого импорта `Services/`.

### 5. Copy fidelity — сравнение с UI-SPEC §Copywriting Contract

**PASS с одним drift (L-01).** Все основные строки совпадают побайтово:
- «УЧЁТНЫЕ ДАННЫЕ», «КОНФИДЕНЦИАЛЬНОСТЬ» — точно
- «Введите Client ID», «Введите Client Secret» — точно
- «Сохранить», «Проверить», «Очистить» — точно
- «Аудио и текст отправляются в Сбер GigaChat» — точно
- «Перед первым использованием...» — точно
- «Принять и включить Cloud» — точно
- «Удалить ключи API?» / «Удалить» / «Отмена» / «Cloud-режим станет недоступен...» — точно
- «Не настроено», «Проверяю подключение…», «Подключено» — точно
- Все error strings в `CloudErrorCopy.swift` — точно

Единственное отклонение: `accessibilityHint` «Отозвать согласие» — см. L-01.

### 6. Accessibility — SecureField labels + FocusState

**SecureField** — PASS. Обе поля имеют `.accessibilityLabel(...)` и `.accessibilityHint(...)` по спеку.

**@FocusState** — PASS. `@FocusState private var focus: Field?` объявлен, обе `SecureField` привязаны через `.focused($focus, equals: ...)`. Начальный фокус устанавливается в `.onAppear` через `DispatchQueue.main.asyncAfter(+0.05s)` — обоснованный workaround для NSTextField mounting (Landmine #5).

**StatusDot accessibility** — FAIL (M-01). Отсутствует `accessibilityLabel("Статус подключения: ...")` на объединённом элементе.

**Cloud Picker segment** — FAIL (M-02). Отсутствуют `accessibilityLabel`/`accessibilityHint` по спеку.

### 7. Picker revert guard — `onChange` порядок операций

**PASS.** Строки 537–540:
```swift
if newValue == .cloud, !canActivateCloud {
    selection = oldValue    // ← сначала revert
    showCloudSetup = true   // ← потом открываем disclosure
}
```
Порядок корректен: сначала `selection = oldValue` возвращает Picker к предыдущему значению, затем `showCloudSetup = true`. Нет race bug.

---

## Общая оценка

Код фазы 15 написан аккуратно и в целом следует архитектурным конвенциям проекта. Secret handling выполнен правильно — никаких утечек credentials в логи. Picker revert guard реализован верно. Разделение слоёв соблюдено. Основные проблемы: один нарушитель `!` в `CloudLLMClient` (не новый файл фазы, но попадает в скоуп) и два пропущенных accessibility-лейбла по спеку (M-01, M-02), которые важны для соответствия UI-SPEC.

---

*Reviewed: 2026-04-20T21:35:59Z*
*Reviewer: Claude (gsd-code-reviewer)*
*Depth: standard*
