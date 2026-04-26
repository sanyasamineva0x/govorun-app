---
phase: 12-cloud-llm-client
plan: 01
subsystem: cloud-llm
tags: [gigachat, cloud, http-client, audio-upload, tdd]
dependency_graph:
  requires: [SberAuthService, HTTPClient, LLMClient, SuperTextStyle, NormalizationHints]
  provides: [CloudLLMClient, CloudLLMConfiguration, LLMError.isRetryable]
  affects: [Phase 13 routing, PipelineEngine cloud path]
tech_stack:
  added: [CloudLLMClient, CloudLLMConfiguration]
  patterns: [multipart-upload, sequential-http, retry-with-backoff, auth-error-mapping]
key_files:
  created:
    - Govorun/Services/CloudLLMClient.swift
    - GovorunTests/CloudLLMClientTests.swift
  modified: []
decisions:
  - "JSONSerialization вместо Codable для HTTP request/response (консистентно с прототипом GigaChatClient)"
  - "SequentialMockHTTPClient для тестов двухшагового flow (upload + completions)"
  - "Stub-методы throw вместо fatalError чтобы тесты не крашили test runner"
metrics:
  duration: 10m 49s
  completed: 2026-04-12
  tasks: 2/2
  tests_added: 22
  tests_total: 1205
---

# Phase 12 Plan 01: CloudLLMClient Summary

CloudLLMClient -- HTTP-клиент GigaChat API для audio-in нормализации с двухшаговым flow (upload WAV + chat/completions), retry на completions, AuthError маппинг.

## Task Results

| Task | Name | Commit | Key Changes |
|------|------|--------|-------------|
| 1 | RED -- failing тесты | 63f4e0f | CloudLLMClientTests.swift (22 теста), CloudLLMClient.swift stub |
| 2 | GREEN -- реализация | 88c29c1 | Полная реализация CloudLLMClient, все 22 тестов PASS |

## Implementation Details

### CloudLLMClient.swift

- `CloudLLMConfiguration` -- конфиг с defaults (baseURL, model GigaChat-2-Max, temperature 0.1, timeout 30s, retryDelay 0.5s, maxOutputTokens 128)
- `LLMError.isRetryable` -- extension для rateLimited/serverError/timeout
- `CloudLLMClient: LLMClient, @unchecked Sendable` -- все зависимости let, нет mutable state
- `normalize(_:superStyle:hints:)` -- text-only chat/completions (LLMClient conformance)
- `processAudio(audioData:superStyle:hints:)` -- двухшаговый flow:
  1. Upload WAV через POST /api/v1/files (multipart/form-data)
  2. POST /api/v1/chat/completions с file ID в attachments
- Retry только на completions (429/5xx), один retry с 0.5s backoff
- Upload ошибка -- fail immediately, без retry
- AuthError -> LLMError маппинг (credentialsNotFound, networkError, invalidResponse, tokenParsingFailed)
- CancellationError propagation на всех уровнях

### CloudLLMClientTests.swift

- 22 теста покрывающие: upload формат, completions формат, response extraction, trim, retry 500, retry 429, no retry upload, no retry 400, 4 AuthError маппинга, normalize text-only, empty text, cancellation, configuration defaults/clamping, 5 isRetryable кейсов
- SequentialMockHTTPClient для ordered multi-response flow

## Decisions Made

1. **JSONSerialization** вместо Codable для HTTP bodies -- консистентно с прототипом GigaChatClient, проще для dynamic JSON с optional fields (attachments)
2. **SequentialMockHTTPClient** как local test helper -- MockHTTPClient из HTTPClient.swift поддерживает только один ответ, для двухшагового flow нужен ordered mock
3. **Stub throw вместо fatalError** -- fatalError крашит test runner и не позволяет запустить остальные тесты в RED фазе

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all functionality fully implemented.

## Verification Results

- `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests` -- 22 tests, 0 failures
- `xcodebuild test` full suite -- 1205 tests, 0 failures
- `grep -c "func test_"` -- 22 test methods
- No `protocol LLMClient` in CloudLLMClient.swift (protocol unchanged)
- No stored `var` in CloudLLMClient class (immutable)

## Self-Check: PASSED

- Govorun/Services/CloudLLMClient.swift: FOUND
- GovorunTests/CloudLLMClientTests.swift: FOUND
- .planning/phases/12-cloud-llm-client/12-01-SUMMARY.md: FOUND
- Commit 63f4e0f: FOUND
- Commit 88c29c1: FOUND
