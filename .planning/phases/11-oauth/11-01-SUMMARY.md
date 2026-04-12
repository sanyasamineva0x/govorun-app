---
phase: 11-oauth
plan: 01
subsystem: services/auth
tags: [oauth, actor, tdd, sber, gigachat]
dependency_graph:
  requires: [HTTPClient, CredentialStoring]
  provides: [AuthService, AuthError, OAuthToken, SberAuthService, MockAuthService]
  affects: []
tech_stack:
  added: []
  patterns: [actor-isolation, in-flight-coalescing, credential-provider-closure]
key_files:
  created:
    - Govorun/Services/SberAuthService.swift
    - GovorunTests/SberAuthServiceTests.swift
  modified: []
decisions:
  - "D-01: AuthError без связи с LLMError -- чистая граница auth/llm"
  - "D-03: Без retry -- fail fast, retry на уровне потребителя"
  - "D-04: credentialProvider closure вместо прямой зависимости на CredentialStoring"
  - "D-05: scope дефолт GIGACHAT_API_PERS"
  - "D-06: actor вместо NSLock class -- Swift concurrency"
metrics:
  duration: 4m
  completed: "2026-04-12"
  tasks: 2
  files: 2
  tests_added: 16
  total_tests: 1183
---

# Phase 11 Plan 01: SberAuthService actor-based OAuth Summary

Actor-based OAuth token manager для GigaChat API с in-flight coalescing, TDD (16 тестов RED->GREEN)

## What Was Done

### Task 1 (RED): SberAuthService skeleton + failing tests
- **Commit:** 657c798
- Создан `SberAuthService.swift`: AuthService протокол, AuthError enum (4 кейса с manual Equatable), OAuthToken struct, actor SberAuthService (заглушка), MockAuthService
- Создан `SberAuthServiceTests.swift`: 16 тестов -- success, ошибки (credentials/network/401/parsing), кэш, expired token, формат запроса (RqUID/BasicAuth/body/POST/ContentType), coalescing, equatable, custom URL/scope
- Xcodegen regenerated, 14/16 fail (2 pass: credentialsNotFound совпадает со stub, equatable -- структурный)

### Task 2 (GREEN): Implement SberAuthService actor
- **Commit:** 286e4f7
- `getAccessToken()`: проверка кэша, in-flight coalescing через `Task<String, Error>?`, defer внутри Task body
- `buildTokenRequest()`: POST, Basic auth (base64), RqUID UUID, scope body, Content-Type
- `parseTokenResponse()`: JSONSerialization, expires_at ms -> Date (деление на 1000)
- `isExpiringSoon()`: 5 мин refreshMargin
- 16/16 тестов GREEN, 1183 total suite 0 failures

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| actor вместо NSLock class | Swift strict concurrency, actor isolation вместо ручной синхронизации |
| credentialProvider closure | Не тянем зависимость на CredentialStoring, инжектим closure в init |
| defer внутри Task body | Pitfall 3: defer вне Task не выполнится при cancellation |
| Без retry логики | Fail fast, retry ответственность потребителя (CloudLLMClient) |
| Manual Equatable для AuthError | Associated values требуют ручной реализации ==, нужно для XCTest assert |

## Deviations from Plan

None -- план выполнен точно как написан.

## Threat Mitigations Implemented

| Threat ID | Mitigation |
|-----------|------------|
| T-11-01 | Credentials читаются on-demand через @Sendable closure, не хранятся как свойства actor |
| T-11-04 | In-flight coalescing через stored Task -- concurrent getAccessToken() = один HTTP запрос |
| T-11-06 | Явные проверки типов: access_token as String, expires_at as TimeInterval. Malformed JSON -> tokenParsingFailed |
| T-11-07 | Basic auth через Foundation Data.base64EncodedString(), без кастомной криптографии |

## Self-Check: PASSED

- Govorun/Services/SberAuthService.swift: FOUND
- GovorunTests/SberAuthServiceTests.swift: FOUND
- 11-01-SUMMARY.md: FOUND
- Commit 657c798 (RED): FOUND
- Commit 286e4f7 (GREEN): FOUND
