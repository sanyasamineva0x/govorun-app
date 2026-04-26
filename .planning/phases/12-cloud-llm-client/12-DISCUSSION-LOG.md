# Phase 12: Cloud LLM Client - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 12-cloud-llm-client
**Areas discussed:** Audio API surface, Concurrency model, Retry в двухшаговом flow

---

## Audio API Surface

| Option | Description | Selected |
|--------|-------------|----------|
| Два метода | normalize(text:) для LLMClient + отдельный processAudio(data:style:hints:) для Cloud-пути. Phase 13 вызывает processAudio напрямую. Оба шарят auth/error/response логику | ✓ |
| Новый протокол | CloudProcessing протокол с processAudio(). CloudLLMClient конформит и LLMClient, и CloudProcessing. PipelineEngine инжектит CloudProcessing для cloud-пути | |
| Только audio | CloudLLMClient только для аудио, без LLMClient conformance. Противоречит ROADMAP success criteria | |

**User's choice:** Два метода
**Notes:** Рекомендация Claude — проще для Phase 12, протокол для DI при необходимости добавит Phase 13

---

## Concurrency Model

| Option | Description | Selected |
|--------|-------------|----------|
| class + Sendable | final class, @unchecked Sendable. Нет mutable state — все let. NSLock не нужен. Консистентно с LocalLLMClient | ✓ |
| actor | actor CloudLLMClient. Проще для компилятора, но actor hop без нужды. Сериализует вызовы — второй запрос ждёт первый | |
| На усмотрение | Claude решит при планировании | |

**User's choice:** class + Sendable
**Notes:** Все зависимости let через init, нет mutable state

---

## Retry в двухшаговом flow

| Option | Description | Selected |
|--------|-------------|----------|
| Retry только completions | File ID уже есть — повторить только /chat/completions. Быстрее, меньше трафика. Если upload упал — ошибка сразу | ✓ |
| Retry всё целиком | Перезалить аудио + повторить completions. Проще логика, но удваивает трафик. Защищает от протухшего file ID | |
| На усмотрение | Claude решит при планировании | |

**User's choice:** Retry только completions
**Notes:** Один retry с exponential backoff. SberAuthService обновляет токен автоматически.

---

## Claude's Discretion

- CloudLLMConfiguration shape и defaults
- Внутренняя структура private методов (upload, completions, parseResponse)
- isRetryable extension, multipart формат, naming

## Deferred Ideas

None
