# Phase 13: Mode & Routing - Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Третий продуктовый режим Cloud в ProductMode. Pipeline маршрутизирует аудио через CloudLLMClient.processAudio() минуя локальный STT и LLM. Standard и Super работают без изменений. Cloud доступен только при наличии credentials.

</domain>

<decisions>
## Implementation Decisions

### Cloud Audio Routing
- **D-01:** Ветвление внутри PipelineEngine. В начале processing flow проверяем productMode. Если .cloud — вызываем processAudio напрямую на cloud client, пропускаем STT+LLM. Одна точка fork-а, минимальные изменения.
- **D-02:** CloudLLMClient инжектится в PipelineEngine рядом с LLMClient (через updateCloudLLMClient или аналогичный метод). PipelineEngine хранит optional ссылку на cloud client.

### usesLLM Guard Audit
- **D-03:** ProductMode получает `usesLocalLLM` (true только для .superMode) и `isCloud` (true только для .cloud). `usesLLM` возвращает true для обоих (super и cloud).
- **D-04:** Все 5 guard-ов в AppState, которые триггерят локальную инфраструктуру (llama-server start, model download, LLMRuntimeManager), переключаются с `usesLLM` на `usesLocalLLM`. Cloud не запускает llama-server и не скачивает модель.

### CloudLLMClient Lifecycle
- **D-05:** Lazy creation при переключении на Cloud. `applyProductMode(.cloud)` создаёт SberAuthService + CloudLLMClient, передаёт в PipelineEngine. Когда Cloud не используется — нет оверхеда.
- **D-06:** AppState владеет CloudLLMClient instance (stored property, optional). Пересоздаётся при каждом переключении на Cloud (credentials могли измениться).

### Credentials Gate (MODE-04)
- **D-07:** Два уровня защиты: (1) guard в `applyProductMode(.cloud)` проверяет `credentialStore.get()` — нет credentials → не переключается, логирует warning. (2) `@Published cloudAvailable: Bool` свойство в AppState для UI (Phase 15 использует для disable Cloud опции в picker).
- **D-08:** Пользователь вводит ключи через UI настроек (Phase 15), приложение сохраняет в Keychain через CredentialStore. Проверка credentials — через CredentialStore.get().

### Claude's Discretion
- Конкретная реализация ветвления в PipelineEngine (новый метод processCloudAudio vs if/switch в существующем flow)
- Naming: updateCloudLLMClient vs setCloudClient vs другое
- Нужен ли отдельный протокол для audio-in path (CloudAudioProcessing) или достаточно конкретного типа
- ProductMode.title для .cloud ("Говорун Cloud" vs "Cloud")

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Текущий проект (Phase 10-12 output)
- `Govorun/Models/ProductMode.swift` — ProductMode enum (добавить .cloud case, usesLocalLLM, isCloud)
- `Govorun/App/AppState.swift` — applyProductMode (строка 638), applyLLMConfiguration (строка 662), 5 usesLLM guard sites, init с LocalLLMClient
- `Govorun/Core/PipelineEngine.swift` — updateLLMClient(), productMode property, processing flow
- `Govorun/Services/CloudLLMClient.swift` — CloudLLMClient (Phase 12 output), processAudio method
- `Govorun/Services/LLMClient.swift` — LLMClient протокол, LLMError enum
- `Govorun/Services/SberAuthService.swift` — AuthService протокол, SberAuthService actor
- `Govorun/Services/HTTPClient.swift` — HTTPClient протокол
- `Govorun/Services/SberTrustPolicy.swift` — TrustPolicyProviding, URLSession creation
- `Govorun/Storage/CredentialStore.swift` — CredentialStoring протокол

### Requirements
- `.planning/REQUIREMENTS.md` — MODE-01 (ProductMode.cloud), MODE-02 (cloud routing), MODE-03 (zero regression), MODE-04 (credentials gate), CLOUD-04 (no local STT in cloud)

### Architecture Research
- `.planning/research/ARCHITECTURE.md` — ProductMode.cloud enum sketch, isCloud property
- `.planning/research/FEATURES.md` — applyProductMode changes, guard audit notes
- `.planning/research/PITFALLS.md` — LLMClient snapshot warning, pipeline routing notes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PipelineEngine.updateLLMClient()` — уже принимает любой LLMClient. CloudLLMClient конформит.
- `CredentialStoring.get()` — проверка наличия credentials
- `SberTrustPolicy` → `urlSession` — готовый HTTPClient для CloudLLMClient
- `SberAuthService(httpClient:credentialProvider:)` — готов к созданию

### Established Patterns
- `applyProductMode` + `applyLLMConfiguration` — паттерн отложенного применения (pending → apply when idle)
- `@unchecked Sendable + NSLock` для PipelineEngine — thread-safe mutable state
- DI через init, хранение через stored properties в AppState

### Integration Points
- `AppState.applyProductMode(.cloud)` — точка входа
- `PipelineEngine` — fork point для cloud audio
- `SettingsStore.productMode` — persistence режима (уже поддерживает Codable enum)
- Phase 14: NormalizationGate получит cloud output, Phase 15: UI для credentials и mode picker

</code_context>

<specifics>
## Specific Ideas

- Phase 12 D-02: processAudio вызывается напрямую, минуя LLMClient interface. Протокол для audio-path — ответственность Phase 13.
- Cloud pipeline: AudioCapture → WAV data → CloudLLMClient.processAudio() → normalized text → post-processing (snippets, gate). STT полностью пропущен.
- `.planning/research/ARCHITECTURE.md` содержит sketch ProductMode.cloud с isCloud property — использовать как референс.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-mode-routing*
*Context gathered: 2026-04-12*
