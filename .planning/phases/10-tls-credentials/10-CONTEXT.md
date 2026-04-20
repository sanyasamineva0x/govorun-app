# Phase 10: TLS & Credentials - Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Фаза доставляет TLS trust layer для Sber API и безопасное хранение API credentials в Keychain. Три компонента: (1) SberRootCA.pem бандлинг и загрузка, (2) SberTrustPolicy с URLSession delegate для cert pinning на `*.sberbank.ru`, (3) CredentialStore на Security.framework, (4) HTTPClient протокол для инъекции в тесты.

</domain>

<decisions>
## Implementation Decisions

### Credential Store
- **D-01:** Одна пара credentials — только clientId + clientSecret для GigaChat. Без STT/Legacy ключей из прототипа. Расширить можно позже при необходимости.
- **D-02:** Протокол CredentialStoring: три метода — `save(clientId:clientSecret:)`, `get() -> (clientId, secret)?`, `delete()`. Полный lifecycle для UI сброса.
- **D-03:** Реализация через Security.framework (SecItemAdd/SecItemCopyMatching/SecItemDelete), без KeychainAccess SPM. Zero new dependencies.

### Certificate Loading
- **D-04:** Graceful degradation при ошибке загрузки PEM — Cloud режим недоступен, Standard и Super работают как обычно. Ошибка логируется через OSLog.
- **D-05:** Загрузка сертификата в init SberTrustPolicy. Failable initializer (throws или возвращает nil) — ошибка обнаруживается сразу, а не при первом запросе.

### HTTPClient + Trust Architecture
- **D-06:** HTTPClient — простой протокол с `data(for: URLRequest) async throws -> (Data, URLResponse)`. URLSession конформит напрямую (extension). Как в прототипе.
- **D-07:** Trust и HTTP — отдельные injectable concerns. SberTrustPolicy создаёт URLSession с SberTrustDelegate. Эта URLSession подаётся как HTTPClient в SberAuthService и CloudLLMClient через AppState.
- **D-08:** SberTrustPolicy — экземпляр через DI (создаётся в AppState, передаётся через init). Без `static let shared` синглтона. Консистентно с остальным проектом, легко мокать в тестах.

### Claude's Discretion
- Keychain service name и ключи (e.g., `com.govorun.app.credentials`)
- SberTrustDelegate — конкретная реализация URLSessionDelegate для cert validation
- Слой размещения типов (CredentialStore → Storage/, SberTrustPolicy → Services/, HTTPClient → Services/)
- Error enum naming и cases (TrustPolicyError, CredentialStoreError)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Прототип (порт)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Services/SberTrustPolicy.swift` — SberTrustPolicy + SberTrustDelegate реализация (Security + GRPC/NIO — убрать GRPC/NIO, оставить Security)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Services/SberAuthService.swift` — HTTPClient протокол, CredentialStoring протокол (порт контракта)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Storage/CredentialStore.swift` — KeychainAccess реализация (переписать на Security.framework)
- `/Users/sanyasamineva/Desktop/govorun/govorun/Resources/Certificates/SberRootCA.pem` — Сертификат Минцифры для копирования в govorun-app

### Текущий проект
- `Govorun/Services/LLMClient.swift` — LLMError enum (для совместимости error mapping в Phase 11+)
- `.planning/REQUIREMENTS.md` — INFRA-01, INFRA-02, INFRA-03 (requirements для этой фазы)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LLMError` enum в `Services/LLMClient.swift` — готовые cases (networkError, invalidResponse, timeout, rateLimited, serverError) которые Phase 11 AuthError должен маппить
- `LocalLLMConfiguration` паттерн — static defaults + init с validation + environment overrides — референс для CloudLLMConfiguration (Phase 12)
- `PlaceholderLLMClient` — паттерн no-op реализации

### Established Patterns
- Протоколы для всех сервисов + DI через init (не синглтоны)
- `@unchecked Sendable` + `NSLock` для thread-safe классов
- `private enum Keys` для строковых констант (Keychain keys, UserDefaults keys)
- Typed errors: `enum XxxError: Error, Equatable` с `LocalizedError` для user-facing

### Integration Points
- AppState — composition root, создаст SberTrustPolicy и CredentialStore (Phase 13 wiring)
- `Services/` слой — место для SberTrustPolicy.swift, HTTPClient protocol
- `Storage/` слой — место для CredentialStore.swift (или Services/ — Claude's discretion)
- `Resources/Certificates/` — место для SberRootCA.pem (как в прототипе)

</code_context>

<specifics>
## Specific Ideas

- Прототип в `/govorun/` содержит рабочий код для порта — SberTrustPolicy, CredentialStore, HTTPClient protocol. Нужно убрать GRPC/NIOSSL зависимости и заменить KeychainAccess на Security.framework.
- SberRootCA.pem — физический файл сертификата Минцифры — уже есть в прототипе, копировать в govorun-app.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-tls-credentials*
*Context gathered: 2026-04-12*
