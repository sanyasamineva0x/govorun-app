# Phase 11: OAuth - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 11-oauth
**Areas discussed:** Маппинг ошибок, Retry в auth, Конфигурация

---

## Маппинг ошибок

| Option | Description | Selected |
|--------|-------------|----------|
| В CloudLLMClient (рек.) | CloudLLMClient (Phase 12) ловит AuthError и маппит в LLMError. SberAuthService остаётся чистым auth-слоем. | ✓ |
| В SberAuthService | SberAuthService экспортирует хелпер toLLMError(). Проще для Phase 12, но связывает auth с LLM концепцией. | |
| На твоё усмотрение | Claude решает при планировании. | |

**User's choice:** В CloudLLMClient (рек.)
**Notes:** AuthError остаётся чистым auth-типом, маппинг — ответственность потребителя.

---

## Retry в auth

| Option | Description | Selected |
|--------|-------------|----------|
| Нет, fail fast (рек.) | Одна попытка — ошибка наверх. Retry остаётся на CloudLLMClient (Phase 12). Одно место retry логики. | ✓ |
| Да, одна попытка | SberAuthService делает один retry при 503/timeout. Повышает устойчивость, но вложенный retry. | |

**User's choice:** Нет, fail fast (рек.)
**Notes:** Одно место retry — CloudLLMClient. Нет вложенных retry циклов.

---

## Конфигурация

| Option | Description | Selected |
|--------|-------------|----------|
| Init-параметры (рек.) | tokenURL и scope через init с defaults. Тесты подставляют localhost. Без config struct. | ✓ |
| Config struct | SberAuthConfiguration по паттерну LocalLLMConfiguration. Консистентно, но оверкилл. | |
| Hardcode всё | Static let внутри SberAuthService. Для тестов — MockAuthService. | |

**User's choice:** Init-параметры (рек.)
**Notes:** Как в прототипе. Тесты инжектят localhost URL и MockHTTPClient.

---

## Claude's Discretion

- Протокол naming (AuthService vs SberAuthenticating)
- OAuthToken struct shape
- Реализация coalescing через actor
- Размещение файла

## Deferred Ideas

None
