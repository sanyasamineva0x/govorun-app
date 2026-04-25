---
phase: 16-tests
reviewed: 2026-04-25T13:35:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - Govorun/Storage/CredentialStore.swift
  - GovorunTests/CredentialStoreKeychainTests.swift
  - GovorunTests/AppStateCloudShimTests.swift
  - scripts/benchmark-llm-normalization.py
findings:
  critical: 0
  warning: 2
  info: 6
  total: 8
status: issues_found
---

# Phase 16: Code Review Report

**Reviewed:** 2026-04-25T13:35:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Phase 16 closes test coverage gaps for the Cloud стек и добавляет cloud-режим в benchmark-runner. Изменения корректные, безопасные и хорошо изолированы:

- **CredentialStore DI** — `init(serviceOverride:)` чистая non-breaking миграция, `Keys.service → Keys.defaultService`, ничего из production не трогается, тесты крутятся в UUID-namespace.
- **CredentialStoreKeychainTests** — 9 интеграционных тестов с реальным Keychain, корректный teardown, изоляция по UUID, проверка concurrency через `NSLock`. Чисто.
- **AppStateCloudShimTests** — 3 новых error-path теста (saveError → не флипать `cloudAvailable`, deleteError propagation, non-AuthError → wrap в `.networkError`). Семантика корректная.
- **benchmark-llm-normalization.py** — `--mode cloud` через explicit DI (W6 honored для SSL context), in-process token cache с 5-min refresh margin (соответствует SberAuthService), TLS pinning через cafile, cost guard. Stdlib-only, без новых pip-зависимостей.

**Critical: 0** — secrets не утекают, Authorization header не логируется, `.env.bench` в `.gitignore`, no force unwrap в production коде, TLS pinning через явный cafile (не отключение verify).

**Warnings (2):**
- Cost-guard estimate в `--mode cloud` underestimates token usage в `--pipeline-mode full-pipeline` режиме (system prompt ~1-2K токенов на сэмпл игнорируется → guard может не сработать на bencmark'ах с full prompt).
- `test_deleteCloudCredentials_propagatesStoreError` не зеркалит assertion пары: проверяет throw, но не проверяет что `cloudAvailable` остаётся `true` после неуспешного delete (parity с save-test нарушена).

**Info (6):** module-level token cache без lock (single-threaded CLI — безопасно сейчас, но фрагильно к параллелизации), `usage` aggregation excludes warmup samples, force unwrap в test setUp (`UserDefaults(suiteName:)!`), `.env.bench` parser strips quotes наивно, cloud HTTPError body не санитизирован для PII, `Keys.defaultService` теперь не fileprivate (могло быть `private static`).

## Warnings

### WR-01: Cost guard недооценивает full-pipeline token cost

**File:** `scripts/benchmark-llm-normalization.py:572-574`

**Issue:** `estimate_cloud_token_cost(samples_count) = samples_count * 100` рассчитан для llm-only режима (~50 prompt + ~30 output + buffer на сэмпл). Но в `--pipeline-mode full-pipeline` система промпта (production system prompt) ≈ 1-2K токенов добавляется к каждому сэмплу. Реальная стоимость full-pipeline cloud-прогона может быть в 10-20× выше оценки.

Пример: 500 сэмплов в full-pipeline режиме:
- Estimate: 500 × 100 = 50 000 → cost guard НЕ сработает (`> 50_000` ложь, exact equality).
- Реальная: 500 × (1500 prompt + 60 output) ≈ 780 000 токенов.

Граница в коде использует `>` а не `>=`, что для оценки 50000 (exactly threshold для 500 сэмплов) НЕ триггерит guard. Combined с underestimate — реальный free-budget (2M токенов) может быть пробит «тихо» на больших датасетах.

**Fix:**
```python
def estimate_cloud_token_cost(
    samples_count: int,
    *,
    pipeline_mode: str,
    has_system_prompt: bool,
) -> int:
    """Грубая оценка токенов: учитывает system prompt в full-pipeline mode."""
    per_sample = 100  # llm-only: ~50 prompt + ~30 output + buffer
    if pipeline_mode == "full-pipeline" and has_system_prompt:
        per_sample = 1700  # ~1500 system prompt + ~150 user/output
    return samples_count * per_sample

# В main():
estimated = estimate_cloud_token_cost(
    len(dataset),
    pipeline_mode=args.pipeline_mode,
    has_system_prompt=bool(args.system_prompt_file or args.pipeline_mode == "full-pipeline"),
)
if estimated >= 50_000 and not args.force_cost:  # >= вместо >
    ...
```

Альтернатива: оставить grov-оценку, но сменить threshold с `> 50_000` на `> 25_000`, чтобы заложить запас на full-pipeline.

### WR-02: Asymmetric assertions в delete error-path тесте

**File:** `GovorunTests/AppStateCloudShimTests.swift:126-135`

**Issue:** `test_saveCloudCredentials_propagatesStoreError_keepsCloudAvailableFalse` проверяет ОБА: throw + `cloudAvailable` НЕ меняется (line 123). Зеркальный delete-тест (`test_deleteCloudCredentials_propagatesStoreError`) проверяет только throw, но НЕ проверяет что `cloudAvailable` остаётся `true` после неуспешного delete. AppState contract (AppState.swift:380-383): `try credentialStore.delete(); cloudAvailable = false`. При throw присвоение скипается, что нужно явно зафиксировать в тесте — иначе регрессия (например, refactoring к `do/try/catch` который флипает state в catch) пройдёт незамеченной.

**Fix:**
```swift
func test_deleteCloudCredentials_propagatesStoreError() throws {
    let store = MockCredentialStore()
    try store.save(clientId: "abc", clientSecret: "xyz")
    store.deleteError = CredentialStoreError.deleteFailed(-25300)
    let (appState, _) = makeAppState(credentialStore: store)
    XCTAssertTrue(appState.cloudAvailable, "до delete cloudAvailable=true (creds в store)")

    XCTAssertThrowsError(try appState.deleteCloudCredentials()) { error in
        XCTAssertEqual(error as? CredentialStoreError, .deleteFailed(-25300))
    }

    XCTAssertTrue(appState.cloudAvailable, "при ошибке delete cloudAvailable не должен флипаться на false")
    XCTAssertNotNil(store.get(), "Keychain тоже не должен очиститься")
}
```

## Info

### IN-01: Module-level token cache без lock

**File:** `scripts/benchmark-llm-normalization.py:490-494`

**Issue:** `_SBER_TOKEN_CACHE` — module-level mutable dict, читается/пишется в `obtain_sber_token` без lock. Сейчас CLI single-threaded → безопасно. Docstring комментирует «process-local, short-lived» — окей. Но если кто-то переведёт sample-loop на `concurrent.futures.ThreadPoolExecutor` для ускорения cloud-прогонов, race на проверке `cached and exp > now + 300` создаст double-fetch (или хуже — read-during-write inconsistency). Phase 17 могут касаться этого.

Также: при импорте модуля (например, для unit-тестов на `obtain_sber_token`) cache переживёт между тестами и приведёт к flaky behaviour, если кто-то начнёт мокать `urlopen`.

**Fix:** Если W6-подобный pattern требует «no module-level mutable state» расширить и на token cache — обернуть в класс:
```python
class SberTokenCache:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._token: str | None = None
        self._expires_at: float = 0.0

    def get_or_refresh(self, fetch_fn: Callable[[], tuple[str, float]]) -> str:
        with self._lock:
            now = time.time()
            if self._token and self._expires_at > now + 300:
                return self._token
            self._token, self._expires_at = fetch_fn()
            return self._token
```
Создать инстанс в `main()`, передавать через DI как `cloud_ssl_ctx`. Можно отложить до Phase 17 — пометить TODO.

### IN-02: Force unwrap `UserDefaults(suiteName:)!` в тестах

**File:** `GovorunTests/AppStateCloudShimTests.swift:14`

**Issue:** `UserDefaults(suiteName: suiteName)!` — force unwrap. CLAUDE.md говорит «No force unwrap (`!`) in production code» — тесты технически не production, и `UserDefaults(suiteName:)` для уникального UUID-имени не должен возвращать nil. Но pattern всё же лучше согласовать с проектом: множество других тестовых файлов (например, `SettingsStoreTests`) могут использовать тот же приём, или наоборот — guard. Проверить и стандартизировать.

**Fix (опционально):**
```swift
guard let defaults = UserDefaults(suiteName: suiteName) else {
    XCTFail("Не удалось создать UserDefaults для \(suiteName)")
    return
}
```
Или вынести в helper `makeTestDefaults()` shared между cloud-shim тестами и SettingsStore-тестами.

### IN-03: Usage aggregation исключает warmup samples

**File:** `scripts/benchmark-llm-normalization.py:1212-1219`

**Issue:** `cloud_usage_total_tokens` суммируется только из `recorded_rows`, но `recorded_rows` пропускает warmup-сэмплы (line 1184: `if index >= args.warmup`). Warmup-сэмплы тоже жгут реальные токены в cloud-прогоне, но в финальном summary они не учтены — отчётный cost будет ниже фактического на `args.warmup × ~100` токенов (default warmup=1, минор).

**Fix:** Заводить отдельный counter `cloud_usage_total_including_warmup` или агрегировать прямо в loop'е:
```python
cloud_usage_total = 0
# в основном loop'e после result.update:
if args.mode == "cloud":
    row_usage = result.get("usage") or {}
    if isinstance(row_usage, dict):
        tt = row_usage.get("total_tokens")
        if isinstance(tt, (int, float)):
            cloud_usage_total += int(tt)
# в summary update:
summary["cloud_usage_total_tokens"] = cloud_usage_total  # включая warmup
```
Альтернатива: задокументировать в `16-BENCHMARK-RESULTS.md` что warmup токены не учтены (если важно для финансового учёта).

### IN-04: `.env.bench` парсер примитивен

**File:** `scripts/benchmark-llm-normalization.py:472-486`

**Issue:** Простая строчная разборка `KEY=VALUE`:
- `val.strip().strip('"').strip("'")` снимает SAME quote с обеих сторон, но ALSO снимет mixed quotes: `'"value"'` → `value`. Для секрета с literal `"` или `'` в значении это разрушительно (Sber secrets обычно alphanumeric, но не гарантированно).
- Не поддерживает экранирование (`\=`, `\"`).
- Не поддерживает multi-line values.
- Игнорирует `export KEY=VALUE` prefix.

Для bench-credentials (Sber UUID-формат, без спецсимволов) — fine. Но если кто-то скопирует Linux-style `.env` файл с `export` или escapes, тихо распарсит криво.

**Fix:** Либо документировать ограничение в `.env.bench.example`, либо использовать `python-dotenv` (но это новая dependency, нарушает stdlib-only). Простейшее улучшение:
```python
if line.startswith("export "):
    line = line[len("export "):]
key, val = line.split("=", 1)
val = val.strip()
# Strip outer quotes ОДИН раз, и только если pair совпадает:
if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
    val = val[1:-1]
creds[key.strip()] = val
```

### IN-05: HTTPError response body не санитизируется

**File:** `scripts/benchmark-llm-normalization.py:635-641, 720-722`

**Issue:** При HTTP-ошибке cloud-запроса `body = exc.read().decode("utf-8", errors="ignore")` сразу попадает в `LLMRequestError(f"HTTP {exc.code}: {body}")`. Если Sber API echo'ит request payload в error response (некоторые API так делают для отладки 400-х), body может содержать `user_text` (PII транскрипты пользователя) и `system_prompt`. Эти сообщения логируются в `output_path` JSONL (line 1149: `result["error"] = str(exc)`) и могут попасть в коммитимые `build/*-summary.json` или `build/*-results.jsonl` если кто-то вручную коммитит build/.

Для local llama-server (line 720-722) то же самое.

Authorization Bearer header **НЕ** echo'ится — Sber так не делает, и body — это response body, не request. Так что прямой утечки токена нет. Это про PII транскриптов.

**Fix:** Truncate body до 512 символов (как уже делается для OAuth, line 538: `body_snippet = exc.read()[:512]`):
```python
body = exc.read().decode("utf-8", errors="ignore")[:512]
raise LLMRequestError(f"HTTP {exc.code}: {body}") from exc
```
И/или префиксовать предупреждением в README/`.env.bench.example`: «Errors могут попасть в `build/*.jsonl` — не commit'ить эти файлы (они в `.gitignore`).».

Проверить `.gitignore` для `build/llm-normalization-benchmark-results.jsonl` — если уже игнорируется, риск минимален.

### IN-06: `Keys.defaultService` теперь не required `private`-уровень

**File:** `Govorun/Storage/CredentialStore.swift:25-29`

**Issue:** До Phase 16 enum `Keys` был приватный (использовался только внутри CredentialStore). Сейчас `defaultService` всё ещё внутри `private enum Keys` — это OK. Но раз теперь имя `defaultService` — возможно, стоит сделать его `public static let` доступным (или хотя бы internal), чтобы тесты или сторонний код мог сослаться на канонический prod-namespace без hard-code строки `"com.govorun.app.credentials"`.

**Fix (опционально):** Не критично. Если когда-нибудь понадобится exposed canonical service name для diagnostics или migration, рефакторить:
```swift
extension CredentialStore {
    static let defaultService = "com.govorun.app.credentials"
}
```
Покане required.

---

_Reviewed: 2026-04-25T13:35:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
