# Технический долг и области риска — Говорун

Дата: 2026-03-29. Версия: v0.2.0.

---

## 1. Известные баги и нестабильные тесты

### 1.1 Flaky тест `test_stop_then_start_relaunches_worker`
**Файл:** `GovorunTests/ColdStartUITests.swift:485`

Тест проверяет, что после `stop()` → `start()` worker перезапускается. Использует polling-цикл с 20 итерациями по 50 мс — итого до 1 секунды ожидания. Race condition: `start()` запускается в Task (@MainActor), а тест сразу проверяет `mockWorker.startCalled`. На медленном CI Task может не успеть выполниться.

Явно документирован в `CLAUDE.md` как «не блокер».

**Паттерн-проблема:** `ColdStartUITests.swift` содержит ~25 мест с `Task.sleep(nanoseconds: 50_000_000..800_000_000)` для синхронизации с @MainActor Tasks. Это хрупкая замена structured concurrency. На нагруженном CI возможны ложные провалы особенно у тестов со sleep на 800 мс (800-мс задержки в `IntegrationTests.swift:149,185,364,401,440`).

### 1.2 Stale taймаут в `ASRWorkerManager` при быстрой остановке
**Файл:** `Govorun/Services/ASRWorkerManager.swift`

Защита реализована через `_launchAttemptId`, но тест `test_staleTimeout_guard_prevents_state_overwrite` только симулирует guard-логику вручную, а не тестирует реальный timeout closure. Если стартовый timeout (DispatchWorkItem) успеет выполниться после `stop()` до инвалидации ID — state перезапишется. Покрытие через mock, не через реальный timer.

### 1.3 Race condition в toggle-режиме при `tapDisabledByTimeout`
**Файл:** `Govorun/App/NSEventMonitoring.swift:277-291`

Когда система отключает CGEventTap (tapDisabledByTimeout/tapDisabledByUserInput) во время активной toggle-записи, callback `onTapReset()` вызывается. В `AppState` это должно инициировать принудительную деактивацию. Путь: `ActivationTapContext.onTapReset` → `AppState.handleTapReset`. Если между отключением tap'а и вызовом `onTapReset` пользователь уже завершил запись — возможен двойной вызов деактивации. Тест существует (`RecreateMonitorTests`), но CGEventTap не подделывается.

---

## 2. Безопасность

### 2.1 Entitlements: минимальный набор, но без Hardened Runtime проверки на микрофон
**Файл:** `Govorun/Govorun.entitlements`

Только одна entitlement: `com.apple.security.device.audio-input`. Это корректно для офлайн-приложения. Нет `com.apple.security.network.client` — это намеренно (все запросы только localhost или HuggingFace для скачивания модели). Однако `URLSession.shared` используется в `SuperModelDownloadManager` и `LLMRuntimeManager` без явного ограничения домена. При добавлении любой сетевой функциональности в будущем потребуется добавить network entitlement.

**Отдельная проблема:** отсутствие `com.apple.security.network.client` в entitlements, но наличие сетевых запросов в `SuperModelDownloadManager.swift:264` и `LLMRuntimeManager.swift:676` — это технически допускается через Hardened Runtime, но стоит явно задокументировать.

### 2.2 Accessibility permission — единственная точка отказа без graceful fallback
**Файл:** `Govorun/App/NSEventMonitoring.swift:25-32`

Если `CGEventTap.create` завершается неудачей (нет Accessibility permission), код молча переходит на `NSEvent.addGlobalMonitorForEvents`. Fallback-монитор не подавляет события (только слушает), то есть activation key будет проходить в другие приложения. Есть только `print(...)` вместо UI-уведомления пользователю. TODO задокументирован: `// TODO: показать Accessibility хинт пользователю (сейчас только print)`.

Аналогичная ситуация в `AppState.swift:1103` — global Esc monitor не создаётся без permission, только `print`.

### 2.3 Path traversal в Python worker — частичная защита
**Файл:** `worker/server.py:176-187`

Реализована проверка `realpath` + allowlist `/tmp/`, `/private/tmp/`. Но `allowed_prefixes` содержит строку `"/tmp/"` — если WAV-путь передан как `/tmp/../../etc/passwd`, `realpath` разрешит его до абсолютного пути вне `/tmp/`, и проверка пройдёт корректно. Защита работает правильно, но она хрупка: строковое сравнение через `startswith` без trailing slash нормализации — `/tmp/govorun.wav` и `/tmpX/file` — оба начинаются с `/tmp`, но второй не должен проходить. Реально `realpath` нормализует пути, поэтому `/tmpX` не совпадёт с `/tmp/`. Риск минимальный, но стоит добавить trailing slash в проверку.

### 2.4 Clipboard sandwich — временное засорение буфера обмена
**Файл:** `Govorun/App/AXTextInserter.swift:140-152`, `Govorun/Core/TextInserter.swift:140-146`

Стратегия 3 (clipboard fallback): сохраняет текущий clipboard, вставляет текст, восстанавливает. Если приложение крашнется между `setString` и `restore` — пользователь потеряет содержимое clipboard. 0.3-секундная задержка `pasteDelay` — это magic number, недостаточная для медленных приложений (виртуальные машины, Electron-приложения с задержкой обработки paste). Нет механизма отката при ошибке вставки.

### 2.5 Monkey-patching внутренних компонентов HuggingFace Hub
**Файл:** `worker/server.py:68-111`

Патчится приватный модуль `huggingface_hub._snapshot_download` для перехвата progress. Это нестабильный контракт — изменение внутреннего API HuggingFace может сломать progress reporting без ошибки при запуске (patch применится к несуществующему символу). Не ломает функциональность, но делает progress индикатор непредсказуемым при обновлении зависимостей.

---

## 3. Производительность

### 3.1 SHA256 всего файла при каждом запуске (fast-path verification)
**Файл:** `Govorun/Services/SuperModelDownloadManager.swift:196-203`

При каждом старте `SuperAssetsManager.check()` → (если файл уже есть) `sha256(ofFileAt: spec.destination)` читает весь 6.5 ГБ GGUF файл побайтово чанками 1 МБ. На M1 это ~15-30 секунд. Fast-path SHA256 проверка выполняется синхронно в `download(from:)` при каждом вызове. Нет кэширования результата на диске. При перезапуске приложения с уже скачанной моделью — каждый раз ~15+ секунд verifying state.

### 3.2 Токенизация в NormalizationGate — O(n*m) регулярные выражения
**Файл:** `Govorun/Core/NormalizationGate.swift:113-127`, `Govorun/Core/NormalizationPipeline.swift:180-215`

5 compiled regex для protected tokens применяются к каждому запросу отдельно. `DeterministicNormalizer.normalize()` также использует ~15 compiled regex паттернов (lazy static, но применяются последовательно). Для коротких фраз это не проблема, но для длинной диктовки (>100 слов) накапливается. Нет бенчмарка для детерминистической части пайплайна.

### 3.3 PipelineEngine: многократное копирование Audio Data
**Файл:** `Govorun/Core/AudioCapture.swift:133-148`, `Govorun/Core/PipelineEngine.swift:315-340`

PCM-данные аккумулируются в `audioBuffer: Data` через `append`, затем передаются в STT через WAV файл в /tmp. Для длинных записей (2+ минуты ≈ ~60 MB PCM) происходит: буфер в памяти → запись в /tmp → чтение worker → ONNX inference. Три копии данных одновременно. При включённой истории (`saveAudioHistory`) добавляется четвёртая копия в Application Support.

### 3.4 RMS уровень вычисляется на каждом 100ms буфере float-итерацией
**Файл:** `Govorun/Core/AudioCapture.swift:227-244`

`rmsLevel()` итерирует все float samples вручную в Swift. Для PCM 16kHz × 100ms = 1600 сэмплов — приемлемо. Но формат входного микрофона (напр. 48kHz stereo) конвертируется в 16kHz mono, и RMS считается от **исходного** буфера до конвертации (`buffer.rmsLevel()` вызывается на pre-conversion buffer). Это значит VU-meter показывает уровень в native sample rate, а не в 16kHz. Визуально не важно, но семантически неточно.

---

## 4. Хрупкие архитектурные области

### 4.1 AppState — monolithic composition root, ~1200 строк
**Файл:** `Govorun/App/AppState.swift`

Весь wiring в одном файле: 8+ private методов `wire*()`, pending settings для 4 типов параметров, complex state machines (productMode pending, activationKey pending, recordingMode pending, LLM config pending). Добавление нового параметра требует: поле current + поле pending + обработка в `wireSettingsChange` + обработка в `applyPendingSettings`. Легко забыть одну ветку. Паттерн pending + apply не тестируется end-to-end — только отдельные unit тесты.

### 4.2 Два слоя обработки activation key с дублирующейся логикой
**Файл:** `Govorun/Core/ActivationKeyMonitor.swift`, `Govorun/App/NSEventMonitoring.swift`

`ActivationKeyMonitor` содержит полную state machine (isKeyDown, isActivated, isArmed, comboModifiersDown + timers). `ActivationTapContext` в `NSEventMonitoring.swift` содержит **параллельную** state machine (pendingDown, activated, toggleRecording, comboModifiersHeld + timer). Обе машины работают одновременно — tap-level и monitor-level. Tap-level подавляет события, monitor-level принимает callbacks от tap. При рассинхронизации (tap disabled, быстрые нажатия) состояния могут рассинхронизироваться. Это источник периодических "призрачных активаций".

### 4.3 SwiftData migration — ручное управление без versioned schemas
**Файл:** `Govorun/GovorunApp.swift`, `Govorun/Models/HistoryItem.swift`

`AppModelContainer.shared` создаёт `ModelContainer` с двумя `ModelConfiguration` без `SchemaMigrationPlan`. Недавние коммиты `fix: HistoryItem.textMode data strategy + дедупликация миграций` и `fix: полный migration scope — переезд типов, PipelineResult, аналитика` указывают на то, что миграции были проблемой. Без формального `VersionedSchema` + `MigrationStage` — SwiftData использует lightweight migration автоматически, что ломается при переименовании/удалении полей. При добавлении нового поля в `HistoryItem` (например, для text styles v2) нужна явная миграция иначе `ModelContainer` упадёт с `fatalError`.

### 4.4 `CURRENT_PROJECT_VERSION = 0` — сломан Sparkle update flow
**Файл:** `project.yml:49`

`CURRENT_PROJECT_VERSION` (CFBundleVersion) = 0 для v0.2.0. Sparkle использует этот номер для сравнения версий. Если 0 меньше предыдущего значения 10 (v0.1.10), Sparkle может не предложить обновление или показать некорректный UI. Был явный коммит `fix: CURRENT_PROJECT_VERSION = 0 для v0.2.0` — возможно намеренный сброс для новой ветки нумерации, но это нестандартное решение. В `appcast.xml` последняя версия — v0.1.10 (sparkle:version=10), а v0.2.0 не добавлена в appcast.

### 4.5 Monkey-patch onnxruntime InferenceSession для принудительного CPU
**Файл:** `worker/server.py:113-120`

`ort.InferenceSession.__init__` патчится для всех последующих сессий, чтобы форсировать `CPUExecutionProvider`. Комментарий объясняет: GigaAM e2e_rnnt не поддерживает CoreML. Проблема: патч применяется глобально на уровне класса — если в будущем добавится второй ONNX-инференс (например для другой модели), он тоже будет принудительно CPU без возможности использовать ANE/CoreML.

### 4.6 `LLMOutputContract.rewriting` — мёртвый код
**Файл:** `Govorun/Core/NormalizationGate.swift:7`, `Govorun/Core/NormalizationGate.swift:210-244`

`evaluateRewriting()` реализована и покрыта тестами, но `TextMode.llmOutputContract` всегда возвращает `.normalization`. Комментарий в коде: `"Rewriting останется для следующего этапа"`. При реализации text styles v2 придётся активировать или переработать эту ветку — код сейчас drift от последних спецификаций (spec удалил TextMode, заменил на SuperTextStyle).

---

## 5. Технический долг

### 5.1 Смешанное использование `print()` и `Logger` (OSLog)
**Файл:** `Govorun/App/AppState.swift` (~8 print), `Govorun/App/NSEventMonitoring.swift` (2 print), `Govorun/Services/ASRWorkerManager.swift` (4 print), `Govorun/Storage/SettingsStore.swift` (3 print), и другие

Большинство production кода использует `Logger` через OSLog, но ~25 мест используют `print()` напрямую. `print()` не фильтруется в Console.app, не поддерживает privacy levels, медленнее. Особенно критично в hot path: `AudioCapture.swift:221` — `print("[AudioCapture] mData is nil")` может вызываться на audio callback thread.

### 5.2 `@unchecked Sendable` на 11 классах
**Файлы:** `PipelineEngine.swift`, `TextInserterEngine.swift`, `SuperModelDownloadManager.swift`, `SuperAssetsManager.swift`, `LocalLLMClient.swift`, `ASRWorkerManager.swift`, `LLMRuntimeManager.swift`, `SnippetEngine.swift`, `SystemSoundPlayer.swift`, + 2 внутренних класса

Каждый из них использует `NSLock` вручную. Это корректный паттерн для Swift < 6 strict concurrency, но означает что Swift concurrency checker не контролирует эти типы. Любое добавление нового поля без lock защиты будет data race без compile-time ошибки.

### 5.3 Детерминированный нормализатор — только для русского языка разработчика
**Файл:** `Govorun/Core/NormalizationPipeline.swift:14-52`

Hardcoded словари брендов (Jira, Slack, Notion, GitHub, Zoom, Sparkle, PDF, CSV, iOS, ML, QA), filler words (эм, ну, типа, вот), canonical phrase replacements (jira server, project.yml) — это персональные словари разработчика. Легко конфликтуют с пользовательскими данными. Нет механизма отключить конкретный canonical replacement без изменения кода. `DictionaryStore` существует для пользовательских замен, но canonical replacements встроены в код.

### 5.4 `SnippetReinserter.mechanicalFallback` — хрупкий fallback
**Файл:** `Govorun/Core/PipelineEngine.swift:150-183`

Используется когда LLM отклонён gate'ом или reinsertion не удалась. Алгоритм: ищет trigger в тексте, строит `"trigger: content"` форматирование. Если trigger не найден — возвращает `"Trigger: content"` без контекста (весь исходный текст теряется). Тест-файл `SnippetReinserterTests.swift` должен покрывать edge cases, но mechanicalFallback для embedded snippets — это деградация качества, и её частота не отслеживается отдельно от `snippetFallbackUsed` поля.

### 5.5 Polling в PostInsertionMonitor — AX чтение каждые 2 секунды
**Файл:** `Govorun/Core/PostInsertionMonitor.swift:38-39`

60 секунд мониторинга × каждые 2 секунды = до 30 вызовов `readFocusedText()` → `AXUIElementCopyAttributeValue` после каждой вставки. AX API блокирующее, вызывается на main thread (через Task @MainActor). Для длинных документов (Notion, Word) чтение AXValue может занимать 50-200 мс на вызов. Если пользователь делает 5 вставок подряд — одновременно висит несколько monitor instances до их stopMonitoring. Проверка на перекрытие сессий существует через `stopMonitoring()` в начале, но только для текущего instance.

### 5.6 AudioHistoryStorage — нет TTL/cleanup
**Файл:** `Govorun/Storage/AudioHistoryStorage.swift`

WAV файлы сохраняются в `~/Library/Application Support/com.govorun/AudioHistory/`. `HistoryStore.maxItems = 100` ограничивает `HistoryItem` записи, но при удалении item вызывается `deleteFile` — это корректно. Однако `deleteAllFiles()` удаляет только директорию, а WAV файлы без соответствующего HistoryItem (если SwiftData запись удалена, а файл остался из-за краша) накапливаются бессрочно. Нет периодической очистки осиротевших файлов.

### 5.7 `SettingsStore` — нет типизированной миграции настроек
**Файл:** `Govorun/Storage/SettingsStore.swift:51-54`

Существует только одна миграция: `"hold"` → `"pushToTalk"` для recordingMode. Будущие enum расширения (текстовые стили v2, новые TextMode значения) потребуют аналогичных миграций. Нет инфраструктуры для версионированных миграций настроек. При добавлении нового defaultTextMode значения — старые пользователи увидят fallback на "universal" (что корректно), но явного upgrade path нет.

---

## 6. Code-signing и дистрибуция

### 6.1 Unsigned DMG — macOS Gatekeeper quarantine
**Файл:** `scripts/build-unsigned-dmg.sh`, `CLAUDE.md:53`

CLAUDE.md явно документирует: "DMG — единственный надёжный способ тестирования. Accessibility сбрасывается при каждой переустановке." Unsigned app при переустановке теряет Accessibility trust (TCC database привязана к code signature). Для пользователей, устанавливающих обновления вручную (не через Sparkle), это означает повторный grant Accessibility при каждом обновлении. Sparkle обновления сохраняют signature.

### 6.2 Hardened Runtime включён, но без Library Validation
**Файл:** `project.yml` — `ENABLE_HARDENED_RUNTIME: true` в Debug и Release

Нет явного `com.apple.security.cs.disable-library-validation` entitlement. Python.framework (63 МБ) и llama-server встроены в bundle. При дистрибуции без Developer ID notarization (unsigned DMG) пользователь должен вручную снять quarantine (`xattr -cr`). Инструкция в CLAUDE.md учитывает это, но пользовательский опыт ухудшается.

### 6.3 llama-server — нет валидации binary integrity при запуске
**Файл:** `Govorun/Services/SuperAssetsManager.swift:151-170`

`resolveRuntimeBinary()` проверяет только `isExecutableFile`. Нет хэш-проверки бинарника. В SuperModelDownloadManager есть SHA256 для GGUF файла, но для llama-server бинарника (bundled при сборке) — нет. Актуально только при наличии write-доступа к bundle (не-sandboxed app).

---

## 7. Потенциально проблемные внешние зависимости

### 7.1 HuggingFace Hub pinned commit — единая точка отказа для всех скачиваний
**Файл:** `Govorun/Models/SuperModelCatalog.swift:7`

URL модели захардкожен с конкретным commit SHA: `97045b260251cfa86f5ad25638fa2dd074153446`. Если HuggingFace удалит этот commit или repо (policy violation, DMCA, etc.) — все пользователи потеряют возможность скачать модель без обновления приложения. Нет механизма fallback URL или проверки доступности commit.

### 7.2 Python worker wheels — arm64/macOS только, нет Intel fallback
**Файл:** `worker/wheels/`

Все wheel файлы скомпилированы для `macosx_11_0_arm64` или `macosx_12_0_arm64`. В requirements.txt нет Intel (`x86_64`) вариантов. При запуске на Intel Mac (хотя CLAUDE.md явно указывает M1+) — pip установка упадёт. Нет явного check в `setup.sh` или в Swift-коде на архитектуру хоста.

### 7.3 Sparkle autoupdate — appcast.xml не содержит v0.2.0
**Файл:** `appcast.xml`

Последняя запись в appcast — v0.1.10. v0.2.0 добавлен в проект (`project.yml`, `CLAUDE.md`), но appcast не обновлён с соответствующим `<item>`. Пользователи v0.1.10 не получат уведомление об обновлении до v0.2.0.

---

## 8. Отдельные мелкие проблемы

### 8.1 `fatalError` при невалидном regex в static lazy — падение в production
**Файлы:** `Govorun/Core/NormalizationPipeline.swift` (~8 мест), `Govorun/Core/NormalizationGate.swift` (2 места), `Govorun/Core/PipelineEngine.swift:121`, `Govorun/Core/AudioCapture.swift:62`

Все regex паттерны компилируются как `static let` или `nonisolated(unsafe) static let`. Невалидный regex → `fatalError`/`preconditionFailure` → crash приложения при первом обращении. Тесты покрывают happy paths, но явных тестов на "все regex компилируются успешно" нет. При рефакторинге regex-паттерна легко внести синтаксическую ошибку, которая проявится только в runtime.

### 8.2 `SettingsStore` создаётся дважды при старте
**Файл:** `Govorun/GovorunApp.swift:68-70`

В `applicationDidFinishLaunching` создаётся `let settings = SettingsStore()` для передачи в `soundPlayer`, и потом `AppState(soundPlayer:)` создаёт свой внутренний `SettingsStore()`. Два независимых объекта читают UserDefaults — изменение через один не обновляет второй. На практике `AppState.settings` — это master, а внешний `settings` используется только для `soundEnabled`. Это незначительная проблема, но инициирует два `ObservableObject` на одних данных.

### 8.3 `AudioCapture` — thread safety через NSLock, но delegate вызывается без lock
**Файл:** `Govorun/Core/AudioCapture.swift:203-211`

После `lock.unlock()` в `processBuffer()` вызываются `delegate?.audioCapture(...)` без lock. Если delegate изменится между unlock и вызовом (unlikely, но возможно в тестах с быстрыми операциями) — race condition. На практике delegate устанавливается один раз при инициализации, поэтому риск минимальный.

### 8.4 `SuperModelDownloadManager.cancel()` — отменяет только `downloading` state
**Файл:** `Govorun/Services/SuperModelDownloadManager.swift:381-391`

`cancel()` проверяет `guard case .downloading = _state`. Если вызов идёт во время `.checkingExisting` или `.verifying` — cancel игнорируется. UI кнопка Cancel доступна в эти состояния (судя по `isActive`), но нажатие ничего не делает кроме установки `_state = .cancelled`. Задача SHA256 верификации (`.verifying`) может продолжаться несколько минут для 6.5 ГБ файла без возможности прерывания.

### 8.5 `LocalLLMClient` использует `URLSession.shared`
**Файл:** `Govorun/Services/LocalLLMClient.swift:44`

По умолчанию `session: URLSession = .shared`. Shared session имеет глобальные connection limits и не изолирован от других сетевых запросов (Sparkle, HuggingFace download). При одновременном скачивании модели и LLM inference — теоретически возможна конкуренция за TCP connections. На практике все запросы localhost или разные хосты, но dedicated session для LLM была бы надёжнее.
