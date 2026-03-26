# LLM Normalization: MVP Implementation Plan

## Оценка roadmap

Roadmap в правильную сторону, но сейчас в одном документе смешаны:
- validated MVP work (уровни 0-2),
- дальние bets без privacy/spec readiness (уровни 3-8),
- и будущий архитектурный рефакторинг под structured actions.

Главные выводы по текущему репо:
- **Уровень 0 обязателен до выбора модели.** В коде вообще нет bench harness и repeatable корпуса фраз.
- **`TextMode` сейчас не равен продуктовым режимам из roadmap.** В коде это app-aware style (`chat`, `email`, `code`), а не пользовательские режимы `как сказал / чисто / формально`.
- **Safety Gate в roadmap правильный по идее, но слишком амбициозный для первого шага.** В репо нет NER/semantic-similarity стека, значит стартовать нужно с дешёвого heuristic gate в Swift.
- **Уровни 3-4 нельзя начинать до privacy spec.** В коде нет моделей хранения consent/retention/encryption для personalization.
- **Уровень 5+ пока не проектируем.** Текущий string-contract `LLMClient.normalize()` для MVP достаточен.

## План реализации

### Итерация 1. Foundation

Цель: сделать LLM-нормализацию измеримой и безопасной без привязки к конкретной модели.

Скоуп:
- benchmark harness для уровня 0;
- seed-корпус фраз для latency/quality smoke-test;
- `NormalizationGate` в Swift pipeline;
- различение `llmFailed` и `llmRejected`.

Готовность:
- можем подключать локальный LLM backend без риска молча вставлять галлюцинации;
- можем мерить p50/p95/first-token на одном и том же наборе фраз.

### Итерация 2. Local LLM runtime

Цель: заменить `PlaceholderLLMClient`.

Скоуп:
- `LocalLLMClient` поверх локального OpenAI-compatible endpoint или отдельного worker;
- lazy startup / healthcheck / timeout policy;
- конфиг пути к модели и backend;
- bench прогон на реальном железе.

Готовность:
- go/no-go по GigaChat3.1 vs fallback модели основан на реальных замерах.

### Итерация 3. Product modes

Цель: разлепить два разных измерения:
- app context (`chat`, `email`, `code`);
- transform mode (`verbatim`, `clean`, `formal`).

Скоуп:
- отдельная модель режима нормализации;
- mapping prompt-contract → gate-contract;
- UI переключения режима;
- только `formal` получает rewriting gate.

### Итерация 4. Context enrichment

Только после privacy spec:
- window title / file name / selected text;
- per-app denylist;
- явный opt-in.

## Что уже сделано в этой ветке

- Базовый heuristic `NormalizationGate` встроен в стандартный LLM path.
- Pipeline теперь отличает:
  - `llmFailed` — backend упал или timeout,
  - `llmRejected` — backend ответил, но output отклонён gate.
- Добавлены unit-тесты на self-correction и protected tokens.
- Добавлен phase-0 benchmark harness и seed dataset.

## Что делать следующим коммитом

1. Поднять локальный backend (`llama-server` или совместимый endpoint).
2. Прогнать `scripts/benchmark-llm-normalization.py` на seed dataset.
3. Зафиксировать реальные latency/RAM цифры в отдельном report.
4. После go/no-go заменить `PlaceholderLLMClient` на локальный runtime.
