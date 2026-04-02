# Скачивание ИИ-модели для Супер-режима

## Цель

Юзер переключает Говорун в Супер-режим → если ИИ-модель отсутствует, приложение предлагает скачать её (~5.8 ГБ) с Hugging Face. Юзер явно нажимает «Скачать». Поддержка resume, проверка целостности (SHA256), progress UI в настройках, macOS notification по завершении.

**Scope:** скачивание относится только к local managed Super-режиму. При external endpoint (не localhost) SuperAssetsManager уже считает assets ready — download flow не применяется, CTA не показывается.

## Решения

| Вопрос | Решение |
|--------|---------|
| Когда скачивать | Онбординг + Settings (при переключении на Супер) |
| Откуда | Hugging Face, pinned commit URL |
| Resume | Да, HTTP Range + sidecar `.partial.meta` |
| Integrity | SHA256 по завершении |
| Отмена | Да, `.partial` файл остаётся для resume |
| Прогресс | Settings (ProductModeCard) + macOS notification (optional polish) |

## Архитектура

Отдельный сервис `SuperModelDownloadManager` (протокол `SuperModelDownloading`). SuperAssetsManager не знает про скачивание — только discovery + validation. AppState координирует.

```
User toggles Super (local managed, не external endpoint)
  → refreshSuperAssetsReadiness()
  → .modelMissing → UI: CTA "Скачать ИИ-модель для Супер-режима"
  → User нажимает
  → startSuperModelDownload()
    → guard: не уже downloading (isActive computed property)
    → disk space check
    → fast path: файл есть + SHA256 ok → .completed
    → resume check: .partial + .partial.meta → Range request
    → streaming dataTask → append .partial → progress callbacks
    → response check: 206 → append, 200 → truncate + restart
    → SHA256 verification → rename .partial → destination
    → refreshSuperAssetsReadiness() (central path — тот же что при смене settings)
    → macOS notification (optional, best-effort)
```

## Секция 1: SuperModelDownloadManager

Префикс `Super` во всех типах — в проекте уже есть `ModelDownloadState` в `ModelManager.swift` для ASR-модели.

### Протокол

```swift
protocol SuperModelDownloading: AnyObject, Sendable {
    var state: SuperModelDownloadState { get }
    var isActive: Bool { get }  // true for .checkingExisting, .downloading, .verifying
    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? { get set }
    func download(from spec: SuperModelDownloadSpec) async
    func cancel()
    func clearPartialDownload(for spec: SuperModelDownloadSpec)
    func restoreStateFromDisk(for spec: SuperModelDownloadSpec)  // relaunch recovery
}
```

### SuperModelDownloadSpec

```swift
struct SuperModelDownloadSpec {
    let url: URL              // pinned HF commit URL (не /main/)
    let destination: URL      // ~/.govorun/models/gigachat-gguf.gguf
    let expectedSHA256: String
    let expectedSize: Int64   // exact bytes
}
```

### Состояния

```swift
enum SuperModelDownloadState: Equatable {
    case idle
    case checkingExisting       // fast path: SHA256 check
    case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying              // SHA256 final check
    case completed
    case failed(SuperModelDownloadError)
    case cancelled
    case partialReady(downloadedBytes: Int64, totalBytes: Int64)  // после relaunch, .partial найден
}
```

`partialReady` — восстановленное состояние после перезапуска приложения. UI показывает "Скачано X из Y ГБ. Продолжить?" вместо `.idle`.

`.completed` — transient state. После relaunch не восстанавливается: если destination file exists, `restoreStateFromDisk()` оставляет `.idle`, а `refreshSuperAssetsReadiness()` переводит в `.installed`.

### Ошибки

```swift
enum SuperModelDownloadError: Error, LocalizedError, Equatable {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case integrityCheckFailed
    case networkError(String)
    case fileSystemError(String)
}
```

### Sidecar `.partial.meta`

```json
{
  "url": "https://huggingface.co/.../resolve/<commit>/...",
  "expectedSHA256": "abc123...",
  "expectedSize": 5832014592,
  "etag": "\"abc-123\"",
  "downloadedBytes": 2147483648
}
```

При resume: читаем meta → если url или expectedSHA256 не совпадают с текущим spec → удаляем partial, начинаем заново.

### Механика

1. **Fast path**: destination exists → SHA256 check → `.completed` (без сети)
2. **Disk space**: `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`, с буфером 500 МБ
3. **Resume**: `.partial` + `.partial.meta` exists, spec совпадает → `Range: bytes={downloaded}-`
4. **Streaming**: `URLSession.dataTask` → append в `.partial`, обновлять `.partial.meta`
5. **206/200 check**: `206 Partial Content` → append; `200 OK` → truncate partial, restart
6. **Verification**: SHA256 через `CryptoKit` → rename `.partial` → destination
7. **Cleanup**: удалить `.partial.meta`

### Каталог моделей

```swift
enum SuperModelCatalog {
    static let current = SuperModelDownloadSpec(
        url: URL(string: "https://huggingface.co/<repo>/resolve/<pinned-commit>/gigachat-gguf.gguf")!,
        destination: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".govorun/models/gigachat-gguf.gguf"),
        expectedSHA256: "<exact hash>",
        expectedSize: 5_832_014_592
    )
    static let minimumDiskSpaceBuffer: Int64 = 500_000_000
}
```

`SuperModelCatalog.current` — единственный источник spec. Если модель обновится, меняем только здесь.

## Секция 2: AppState wiring

### Зависимости (все через протоколы)

```swift
private let superModelDownloadManager: any SuperModelDownloading  // NEW
private let superAssetsManager: any SuperAssetsManaging            // existing
private let llmRuntimeManager: any LLMRuntimeManaging              // existing
```

### Два независимых published state

```swift
@Published private(set) var superAssetsState: SuperAssetsState = .unknown
@Published private(set) var superModelDownloadState: SuperModelDownloadState = .idle
```

### Восстановление при запуске

Порядок wiring:
1. Привязать `onStateChanged` callback (чтобы UI получил обновление)
2. Вызвать `restoreStateFromDisk(for: SuperModelCatalog.current)`

```swift
// В init AppState:
superModelDownloadManager.onStateChanged = { [weak self] state in
    self?.superModelDownloadState = state
}
superModelDownloadManager.restoreStateFromDisk(for: SuperModelCatalog.current)
```

Если `.partial` + `.partial.meta` найдены и spec совпадает → состояние переходит в `.partialReady(downloadedBytes:totalBytes:)`. Callback уже привязан — UI получит обновление.

### UI по комбинации двух измерений

Download CTA показывается **только** при local managed endpoint (не external).

| superAssetsState | superModelDownloadState | UI |
|---|---|---|
| `.modelMissing` | `.idle` | CTA "Скачать ИИ-модель для Супер-режима (5.8 ГБ)" |
| `.modelMissing` | `.partialReady(...)` | "Скачано X из Y ГБ" + "Продолжить" / "Удалить" |
| `.modelMissing` | `.checkingExisting` | "Проверяю..." |
| `.modelMissing` | `.downloading(...)` | Progress bar + "Отменить" |
| `.modelMissing` | `.verifying` | "Проверяю целостность файла..." |
| `.modelMissing` | `.completed` | Transient → refresh → `.installed` |
| `.modelMissing` | `.failed(.networkError)` | "Не удалось скачать" + "Продолжить скачивание" |
| `.modelMissing` | `.failed(.integrityCheckFailed)` | "Файл повреждён" + "Скачать заново" |
| `.modelMissing` | `.cancelled` | "Скачивание отменено" + "Продолжить" / "Удалить" |
| `.installed` | `*` | "Я готов к работе в Супер-режиме" |
| `.error(msg)` | `*` | "Ошибка: {msg}" + "Проверить снова" + (если файл битый: "Удалить и скачать заново") |
| `.runtimeMissing` | `*` | "Не могу запустить Супер-режим" (без CTA скачивания) |

### Методы AppState

```swift
func startSuperModelDownload() async {
    guard !superModelDownloadManager.isActive else { return }
    guard superAssetsState == .modelMissing else { return }
    await superModelDownloadManager.download(from: SuperModelCatalog.current)
}

func cancelSuperModelDownload() {
    superModelDownloadManager.cancel()
}

func clearPartialSuperModelDownload() {
    superModelDownloadManager.clearPartialDownload(for: SuperModelCatalog.current)
}

func deleteCorruptedModelAndRedownload() async {
    // Удалить текущий файл модели (битый/слишком маленький)
    let spec = SuperModelCatalog.current
    try? FileManager.default.removeItem(at: spec.destination)
    await startSuperModelDownload()
}
```

### Post-download flow

После `.completed` нужны два шага: refresh assets state + conditional runtime start. Сейчас в AppState это две отдельные функции:
- `refreshSuperAssetsReadiness()` (line ~279) — только обновляет `superAssetsState`
- логика start/stop runtime (line ~569) — отдельно, при смене настроек

Вводим coordinator-метод `handleSuperAssetsChanged()`, который внутри делает:

```swift
func handleSuperAssetsChanged() async {
    await refreshSuperAssetsReadiness()
    // та же логика что сейчас в line ~569:
    // guard effectiveProductMode == .superMode
    // guard superAssetsState == .installed
    // → start runtime
    // guard superAssetsState != .installed
    // → stop runtime
}
```

Этот метод **заменяет** существующие вызовы:
- `applyProductMode()` (AppState.swift line ~539) — маршрутизировать через `handleSuperAssetsChanged()`
- `applyLLMConfiguration()` (AppState.swift line ~565) — маршрутизировать через `handleSuperAssetsChanged()`
- post-download `.completed` callback

Одна точка входа — нет расхождений. Существующий код `startLLMRuntimeIfAssetsReady()` сворачивается внутрь этого coordinator-метода.

```swift
// После .completed:
// 1. await handleSuperAssetsChanged()  — refresh + start/stop
// 2. macOS notification (best-effort, не блокирует flow)
```

## Секция 3: UI

### Settings — ProductModeCard

Все тексты от первого лица Говоруна, без упоминания GigaChat.

**Изменение поведения picker:** сейчас `superAvailable` возвращает `false` при `.modelMissing`, и picker откатывает выбор Super обратно на Standard (SettingsView.swift line ~343). Это блокирует доступ к CTA скачивания. Новое поведение: picker разрешает выбор Super при `.modelMissing` — вместо отката показываем CTA скачивания внутри ProductModeCard. Picker блокируется только при `.runtimeMissing`.

```swift
private var superAvailable: Bool {
    switch appState.superAssetsState {
    case .installed, .unknown, .checking, .modelMissing, .error: true
    case .runtimeMissing: false
    }
}
```

**modelMissing + idle:**
- Заголовок: "Мне нужна ИИ-модель"
- Текст: "Чтобы я мог работать в Супер-режиме, скачайте ИИ-модель (5.8 ГБ). Это может занять 5–30 минут."
- Кнопка: "Скачать ИИ-модель"

**modelMissing + downloading:**
- "Скачиваю ИИ-модель..."
- "2.1 / 5.8 ГБ"
- Progress bar
- "36% — ~8 мин" / "Отменить"

**modelMissing + verifying:**
- Spinner + "Проверяю целостность файла..."

**installed:**
- Чекмарк + "Я готов к работе в Супер-режиме"

**failed(networkError):**
- "Не удалось скачать"
- "Скачано 2.1 из 5.8 ГБ. Проверьте интернет-соединение."
- "Продолжить скачивание"

**cancelled:**
- "Скачивание отменено"
- "Скачано 2.1 из 5.8 ГБ. Можно продолжить в любое время."
- "Продолжить" / "Удалить"

**error(msg):**
- "Ошибка: {msg}"
- Кнопка "Проверить снова" → `handleSuperAssetsChanged()`
- Если ошибка связана с файлом модели (слишком маленький, битый) — дополнительная кнопка "Удалить и скачать заново" (удаляет текущий файл + `startSuperModelDownload()`)
- SuperAssetsManager уже кладёт в `.error` и "Model file too small", и "Could not check file size" — для таких случаев одного "Проверить снова" недостаточно, retry зациклится

**runtimeMissing:**
- "Не могу запустить Супер-режим" (picker disabled)

### Онбординг

Последний шаг онбординга: "Хотите Супер-режим? Скачайте ИИ-модель для Супер-режима (5.8 ГБ)". Кнопка "Скачать" / "Пропустить". Тот же `startSuperModelDownload()` через AppState.

В онбординге уже есть шаг "ИИ-модель (~900 МБ)" для ASR (модель распознавания). Тексты разведены: "модель распознавания" (ASR) vs "ИИ-модель для Супер-режима" (LLM).

### macOS Notification

По завершении скачивания: `UNUserNotificationCenter.add()`.
- Title: "Говорун"
- Body: "Я готов работать в Супер-режиме!"

Разрешение на нотификации запрашиваем при первом вызове `startSuperModelDownload()`.

## Тестирование

- `MockSuperModelDownloader: SuperModelDownloading` — все состояния управляются вручную
- Тесты на state transitions (idle → downloading → verifying → completed)
- Тесты на resume logic (partial exists + meta matches → Range request)
- Тесты на meta mismatch (url changed → delete partial, restart)
- Тесты на 206/200 fallback
- Тесты на SHA256 verification (pass/fail)
- Тесты на disk space check
- Тесты на relaunch recovery (restoreStateFromDisk → partialReady)
- Тесты на guards в AppState (duplicate start, wrong mode, external endpoint)
- Тесты на UI state combinations (superAssetsState × superModelDownloadState)

## Файлы

| Файл | Действие |
|------|----------|
| `Govorun/Services/SuperModelDownloadManager.swift` | Создать |
| `Govorun/Models/SuperModelDownloadState.swift` | Создать |
| `Govorun/Models/SuperModelDownloadSpec.swift` | Создать |
| `Govorun/Models/SuperModelCatalog.swift` | Создать |
| `Govorun/App/AppState.swift` | Модифицировать |
| `Govorun/Views/SettingsView.swift` | Модифицировать |
| `Govorun/Views/OnboardingView.swift` | Модифицировать |
| `GovorunTests/SuperModelDownloadManagerTests.swift` | Создать |
| `GovorunTests/IntegrationTests.swift` | Модифицировать |
