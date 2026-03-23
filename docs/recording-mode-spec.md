# Режим работы: Push to Talk / Toggle

## Задача

Добавить настройку «Режим работы» с двумя вариантами:

1. **Push to Talk** (текущее поведение, по умолчанию) — удерживай клавишу для записи, отпусти для остановки
2. **Toggle** — нажми для начала записи, нажми ещё раз для остановки

## Модель данных

### RecordingMode enum

```swift
// Models/RecordingMode.swift (новый файл)
enum RecordingMode: String, Codable, Sendable, CaseIterable {
    case pushToTalk  // default
    case toggle

    var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .toggle: "Toggle"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk: "Удерживайте клавишу для записи, отпустите для остановки"
        case .toggle: "Нажмите для начала записи, нажмите ещё раз для остановки"
        }
    }
}
```

### SettingsStore

```swift
// Storage/SettingsStore.swift — добавить:
var recordingMode: RecordingMode {
    get { /* decode из UserDefaults, default .pushToTalk */ }
    set { /* encode в UserDefaults + objectWillChange.send() */ }
}
```

Ключ `Keys.recordingMode` уже объявлен в SettingsStore.

## Поведение

### Push to Talk (текущее)

```
Key down → 200ms delay → onActivated → запись
Key up → onDeactivated → обработка → вставка
```

Без изменений. Это текущая реализация `ActivationKeyMonitor`.

### Toggle

```
Key down + up (короткое нажатие) → onActivated → запись
Key down + up (повторное) → onDeactivated → обработка → вставка
```

Отличия от Push to Talk:
- Активация происходит при **отпускании** клавиши (keyUp), а не при удержании
- Деактивация — при повторном нажатии + отпускании
- 200ms delay сохраняется (защита от случайных тапов)
- Esc по-прежнему отменяет

### State machine для Toggle

```
idle
  ↓ key down + 200ms delay
armed (ждём key up для активации)
  ↓ key up
recording
  ↓ key down + key up
  onDeactivated → processing → insertion
  ↓ Esc
  onCancelled → idle
```

## Изменения в коде

### 1. Models/RecordingMode.swift — новый файл

Enum с двумя кейсами, Codable, displayName, description.

### 2. Storage/SettingsStore.swift

- Добавить `recordingMode: RecordingMode` property (JSON в UserDefaults, как activationKey)
- Default: `.pushToTalk`
- `resetToDefaults()` сбрасывает на `.pushToTalk`

### 3. Core/ActivationKeyMonitor.swift — главное изменение

Монитор должен знать текущий `recordingMode`.

Два варианта реализации:

**Вариант A: параметр в init**
```swift
init(activationKey: ActivationKey, recordingMode: RecordingMode, eventMonitor: EventMonitoring)
```
При смене режима — recreateMonitor (как при смене клавиши).

**Вариант B: два класса**
```swift
class PushToTalkMonitor: ActivationKeyMonitor { ... }
class ToggleMonitor: ActivationKeyMonitor { ... }
```
Переусложнение — режим влияет только на state machine, не на event handling.

**Рекомендация: Вариант A.** Добавить `recordingMode` в init. Внутри `handleKeyUp` / `handleFlagsChanged` ветвить логику:

```swift
// Push to Talk: key up → deactivate
// Toggle: key up при isActivated → deactivate, key up при !isActivated → activate
```

### 4. App/AppState.swift

- `recreateMonitor` передаёт `recordingMode` из settings
- `handleSettingsChanged` проверяет и `activationKey`, и `recordingMode`

### 5. App/NSEventMonitoring.swift (ActivationEventTap)

Для Toggle mode CGEventTap должен:
- Push to Talk: текущее поведение (suppress key during hold)
- Toggle: suppress только первый tap, не hold. Второй tap — suppress и deactivate.

### 6. Views/SettingsView.swift

В секцию «Поведение» добавить Picker:

```swift
// Между KeyRecorderView и секцией "Поведение"
VStack(alignment: .leading, spacing: 8) {
    SectionHeader(title: "Режим работы", icon: "rectangle.and.hand.point.up.left")

    Picker("", selection: $store.recordingMode) {
        ForEach(RecordingMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
        }
    }
    .pickerStyle(.segmented)

    Text(store.recordingMode.description)
        .font(.caption)
        .foregroundStyle(.secondary)
        .animation(.easeInOut, value: store.recordingMode)
}
.settingsCard()
```

Приписка под Picker меняется при переключении:
- Push to Talk: «Удерживайте клавишу для записи, отпустите для остановки»
- Toggle: «Нажмите для начала записи, нажмите ещё раз для остановки»

### 7. App/StatusBarController.swift

В меню обновить текст статуса с учётом режима:
- Push to Talk: «Зажмите ⌥ и говорите»
- Toggle: «Нажмите ⌥ для записи»

## Тесты

### Новые тесты

- `ActivationKeyMonitorTests` — toggle mode:
  - tap (keyDown + keyUp) → onActivated
  - second tap → onDeactivated
  - quick tap (<200ms) → не активирует
  - Esc во время записи → onCancelled
  - Все три типа клавиш (modifier, keyCode, combo) × toggle mode

- `RecordingModeTests`:
  - Codable roundtrip
  - Default value
  - displayName / description

- `SettingsStoreTests`:
  - recordingMode get/set/reset

- `RecreateMonitorTests`:
  - Смена recordingMode → recreateMonitor

### Обновить существующие

- `IntegrationTests` — добавить toggle mode варианты
- `ColdStartUITests` — проверить что toggle mode корректно отображается

## Edge cases

1. **Смена режима во время записи** — defer до idle (как pendingActivationKey)
2. **Toggle + Esc** — отмена записи, возврат в idle
3. **Toggle + потеря фокуса** — запись продолжается (нет keyUp триггера)
4. **Toggle + sleep/lock** — деактивировать при уходе в сон
5. **CGEventTap для Toggle** — suppress первый tap целиком (keyDown+keyUp), не давать системе. Второй tap — тоже suppress.

## Порядок реализации

1. `RecordingMode` enum + тесты
2. `SettingsStore.recordingMode` + тесты
3. `ActivationKeyMonitor` — toggle logic + тесты
4. `NSEventMonitoring` — tap behavior для toggle
5. `AppState` — recreateMonitor при смене режима
6. `SettingsView` — Picker UI
7. `StatusBarController` — текст меню
8. Integration тесты
