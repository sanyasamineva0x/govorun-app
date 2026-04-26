# Phase 10: TLS & Credentials - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 10-tls-credentials
**Areas discussed:** Credential scope, Cert failure behavior, HTTPClient + Trust bundling

---

## Credential scope

| Option | Description | Selected |
|--------|-------------|----------|
| Одна пара (рекомендую) | Только clientId + clientSecret для GigaChat. Без STT/Legacy. Максимально просто — точно под v2.0. | ✓ |
| Две пары (STT + LLM) | Сохранить разделение из прототипа. Готовность к SaluteSpeech cloud STT. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** Одна пара (рекомендую)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| save + get + delete (рекомендую) | Три метода: save(clientId, secret), get() -> tuple?, delete(). Полный lifecycle. | ✓ |
| save + get только | Без delete. Сброс через save пустыми значениями. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** save + get + delete (рекомендую)
**Notes:** —

---

## Cert failure behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Graceful (рекомендую) | Cloud режим недоступен, Standard/Super работают. Ошибка логируется. | ✓ |
| fatalError (crash) | Как в прототипе. Если PEM нет — баг сборки, не runtime-ошибка. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** Graceful (рекомендую)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| При создании SberTrustPolicy (рек.) | Загрузка PEM в init. Если ошибка — возвращаем nil или throws. | ✓ |
| Lazy при первом запросе | Сертификат грузится только когда Cloud реально нужен. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** При создании SberTrustPolicy (рек.)
**Notes:** —

---

## HTTPClient + Trust bundling

| Option | Description | Selected |
|--------|-------------|----------|
| HTTPClient отдельно (рекомендую) | HTTPClient — простой протокол data(for:). SberTrustPolicy создаёт URLSession. Композиция в AppState. | ✓ |
| SberHTTPClient обёртка | Отдельный класс SberHTTPClient: HTTPClient, который внутри держит trusted URLSession. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** HTTPClient отдельно (рекомендую)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Экземпляр (рекомендую) | SberTrustPolicy создаётся в AppState и передаётся через init. DI-friendly. | ✓ |
| Singleton | Как в прототипе. Проще доступ, но нетестируемо без протокола. | |
| На твоё усмотрение | Claude решит на этапе планирования. | |

**User's choice:** Экземпляр (рекомендую)
**Notes:** —

---

## Claude's Discretion

- Keychain service name и ключи
- SberTrustDelegate реализация URLSessionDelegate
- Слой размещения типов
- Error enum naming и cases

## Deferred Ideas

None — discussion stayed within phase scope
