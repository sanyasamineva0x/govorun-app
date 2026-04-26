# Phase 12: Cloud LLM Client - Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

CloudLLMClient — HTTP-клиент к GigaChat API для audio-in нормализации. Два публичных метода: (1) LLMClient conformance для текстового пути, (2) processAudio для Cloud-пути (upload WAV + chat/completions с attachment). Retry, timeout, AuthError → LLMError маппинг, CloudLLMConfiguration.

</domain>

<decisions>
## Implementation Decisions

### Audio API Surface
- **D-01:** CloudLLMClient имеет два публичных метода: `normalize(text:superStyle:hints:)` (LLMClient conformance) и `processAudio(audioData:superStyle:hints:)` (Cloud audio-in путь). Оба шарят внутреннюю логику auth, error handling, response parsing.
- **D-02:** Phase 13 (routing) вызывает `processAudio` напрямую, минуя LLMClient интерфейс. Протокол для audio-пути (если нужен для DI) — ответственность Phase 13, не Phase 12.
- **D-03:** LLMClient протокол НЕ меняется. CloudLLMClient конформит как есть.

### Concurrency Model
- **D-04:** `final class CloudLLMClient: LLMClient, @unchecked Sendable`. Все зависимости через `let` в init (authService, httpClient, configuration). Нет mutable state → NSLock не нужен. Консистентно с LocalLLMClient.

### Retry Strategy
- **D-05:** Двухшаговый flow: (1) upload WAV → file ID, (2) chat/completions с file ID. При ошибке на шаге 2 (429/5xx) — retry только completions, file ID переиспользуется. При ошибке на шаге 1 (upload) — ошибка сразу, без retry.
- **D-06:** Один retry с exponential backoff (как в success criteria). SberAuthService обновляет токен автоматически — expired token между шагами не проблема.

### Error Mapping (из Phase 11)
- **D-07:** AuthError → LLMError маппинг внутри CloudLLMClient (Phase 11, D-01). credentialsNotFound → networkError, AuthError.networkError → LLMError.networkError, invalidResponse → invalidResponse, tokenParsingFailed → parsingFailed.

### Claude's Discretion
- CloudLLMConfiguration shape и defaults (model: GigaChat-2-Max, temperature: 0.1, timeout: 30s из ROADMAP)
- Внутренняя структура: upload/completions как private методы
- isRetryable extension на LLMError (порт из прототипа)
- Multipart form-data формат для upload WAV
- Naming: processAudio vs processAudioData vs другое

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Прототип (порт)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Services/GigaChatClient.swift` — Рабочий text-only клиент. Порт: sendRequest, parseResponse, isRetryable. НЕ портировать audio upload (его нет в прототипе). Auth, error handling, response parsing — основа для Cloud клиента.

### Текущий проект (Phase 10-11 output)
- `Govorun/Services/LLMClient.swift` — LLMClient протокол (normalize signature), LLMError enum, LocalLLMConfiguration (паттерн для CloudLLMConfiguration), PlaceholderLLMClient
- `Govorun/Services/LocalLLMClient.swift` — Референс: final class + @unchecked Sendable, URLSession, sendChatCompletion pattern
- `Govorun/Services/HTTPClient.swift` — HTTPClient протокол + URLSession conformance (инжектится в CloudLLMClient)
- `Govorun/Services/SberAuthService.swift` — Actor-based OAuth, getAccessToken() для Bearer token

### Requirements
- `.planning/REQUIREMENTS.md` — CLOUD-01 (file upload), CLOUD-02 (chat/completions с attachment), CLOUD-03 (GigaChat-2-Max audio-in), CLOUD-06 (timeout 30s, retry)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LLMError` enum — готовые cases (networkError, invalidResponse, timeout, rateLimited, serverError, parsingFailed). Без изменений.
- `LocalLLMConfiguration` паттерн — static defaults + init с validation. Референс для CloudLLMConfiguration.
- `HTTPClient` протокол + `URLSession` conformance — инжектится через init.
- `SberAuthService.getAccessToken()` — Bearer token для Authorization header.
- Прототип `GigaChatClient`: sendRequest, parseResponse, LLMError.isRetryable extension — портируемая логика.

### Established Patterns
- DI через init (не синглтоны)
- `final class + @unchecked Sendable` для stateless/immutable сервисов
- Typed errors: `enum XxxError: Error, Equatable`
- OSLog logging: `Logger(subsystem: "com.govorun.app", category: "CloudLLMClient")`
- JSONSerialization для request/response (не Codable structs — как в прототипе)

### Integration Points
- AppState (Phase 13) создаст CloudLLMClient, передав SberAuthService и SberTrustPolicy.urlSession
- PipelineEngine (Phase 13) вызовет processAudio для Cloud mode
- NormalizationGate (Phase 14) обработает cloud output

</code_context>

<specifics>
## Specific Ideas

- Прототип GigaChatClient — text-only, audio upload надо построить с нуля по GigaChat API docs.
- GigaChat API: POST `/api/v1/files` (multipart/form-data с WAV) → file ID → POST `/chat/completions` с attachments array.
- `choices[0].message.content` — response text extraction (как в прототипе).
- CloudLLMConfiguration defaults из ROADMAP: model "GigaChat-2-Max", temperature 0.1, timeout 30s.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-cloud-llm-client*
*Context gathered: 2026-04-12*
