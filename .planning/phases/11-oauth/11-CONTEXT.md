# Phase 11: OAuth - Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

SberAuthService — actor-based OAuth token management для GigaChat API. Получение токена с `ngw.devices.sberbank.ru:9443/api/v2/oauth`, кеширование в памяти с auto-refresh за 5 минут до истечения, coalescing конкурентных запросов (actor isolation, no thundering herd). Маппинг AuthError в чистые cases без привязки к LLM-слою.

</domain>

<decisions>
## Implementation Decisions

### Маппинг ошибок
- **D-01:** AuthError остаётся чистым auth-типом (credentialsNotFound, networkError, invalidResponse, tokenParsingFailed). Маппинг AuthError → LLMError — ответственность CloudLLMClient (Phase 12), не SberAuthService. SberAuthService не знает про LLMError.
- **D-02:** Это позволяет переиспользовать SberAuthService для других клиентов (если появятся) без привязки к LLM-концепции.

### Retry
- **D-03:** SberAuthService — fail fast. Одна попытка на HTTP запрос, ошибка возвращается наверх без retry. Retry логика целиком на CloudLLMClient (Phase 12) — одно место retry, нет вложенных retry циклов.

### Конфигурация
- **D-04:** Init-параметры с defaults (как в прототипе): tokenURL, scope, httpClient, credentialProvider через init. Тесты инжектят localhost URL и MockHTTPClient. Без отдельного config struct — оверкилл для auth с фиксированным endpoint.
- **D-05:** Scope hardcoded как default: `GIGACHAT_API_PERS`. Refresh margin: 5 минут (static let).

### Concurrency
- **D-06:** Swift `actor` — первый actor в кодовой базе. Естественная сериализация: конкурентные getAccessToken() вызовы автоматически сериализуются через actor isolation. Не нужен NSLock + continuation array — actor это делает бесплатно.

### Claude's Discretion
- Протокол naming (`AuthService` vs `SberAuthenticating` vs другое)
- OAuthToken struct shape (internal vs public)
- Конкретная реализация coalescing (actor Task + in-flight tracking)
- Error Equatable conformance pattern
- Размещение файла (Services/SberAuthService.swift)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Прототип (порт)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Services/SberAuthService.swift` — Рабочий OAuth с NSLock. Порт контракта: buildTokenRequest, parseTokenResponse, isExpiringSoon. Убрать NSLock → actor, убрать legacy CredentialStoring, добавить coalescing.

### Текущий проект (Phase 10 output)
- `Govorun/Services/HTTPClient.swift` — HTTPClient протокол + MockHTTPClient (уже есть)
- `Govorun/Storage/CredentialStore.swift` — CredentialStoring протокол + MockCredentialStore (уже есть)
- `Govorun/Services/SberTrustPolicy.swift` — TrustPolicyProviding + MockTrustPolicy (уже есть)
- `Govorun/Services/LLMClient.swift` — LLMError enum (reference для совместимости маппинга в Phase 12), AuthError cases должны маппиться чисто

### Requirements
- `.planning/REQUIREMENTS.md` — INFRA-04 (SberAuthService с OAuth, scope GIGACHAT_API_PERS, actor-based)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HTTPClient` протокол + `MockHTTPClient` — готовы, инжектятся в SberAuthService через init
- `CredentialStoring` протокол + `MockCredentialStore` — готовы, SberAuthService использует для получения credentials
- `LLMError` enum — reference для Phase 12 маппинга (networkError, invalidResponse, timeout, rateLimited, serverError)
- Прототип `SberAuthService` — buildTokenRequest(), parseTokenResponse(), isExpiringSoon() портируются

### Established Patterns
- DI через init (не синглтоны) — SberAuthService получает httpClient, credentialProvider через init
- `private enum Keys` для строковых констант
- Typed errors: `enum AuthError: Error, Equatable`
- `@unchecked Sendable + NSLock` — существующий паттерн, но Phase 11 вводит первый `actor`

### Integration Points
- AppState (Phase 13) создаст SberAuthService и передаст в CloudLLMClient
- SberTrustPolicy.urlSession → подаётся как HTTPClient в SberAuthService
- CredentialStore.get() → credentialProvider closure в SberAuthService init

</code_context>

<specifics>
## Specific Ideas

- Прототип в `/Desktop/govorun/` содержит рабочий SberAuthService — порт бизнес-логики (request building, token parsing, expiry check). Concurrency модель меняется: NSLock → actor.
- `expires_at` в Sber API возвращается в миллисекундах Unix timestamp — деление на 1000.0 при парсинге (как в прототипе).
- RqUID = UUID().uuidString в каждом OAuth запросе (как в прототипе).
- Basic auth: base64(clientId:clientSecret) в Authorization header.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-oauth*
*Context gathered: 2026-04-12*
