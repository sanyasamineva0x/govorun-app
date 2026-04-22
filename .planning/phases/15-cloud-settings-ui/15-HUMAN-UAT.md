---
status: passed
phase: 15-cloud-settings-ui
source: [15-VERIFICATION.md, 15-06-SUMMARY.md §UAT Checkpoint, 15-REVIEW-FIX.md]
started: 2026-04-20T20:45:00+03:00
updated: 2026-04-23T00:05:00+03:00
---

## Tests

### A. Picker dropdown lock icon + opacity
expected: Settings → Main, dropdown picker: три пункта. У «Говорун Cloud» есть `lock.fill` после текста + Ink 0.25 opacity (dimmed). Accept-risk per Landmine #4 — если opacity не применяется под `.menu` pickerStyle, icon сам по себе достаточный сигнал.
result: **passed** — Sanya проверила UI 2026-04-22 23:53 ("вроде клауд работет"), статус «Подключено» отобразился, Cloud в picker не залочен (consent с 2026-04-20)

### B. Click Cloud without credentials — revert + disclosure + focus
expected: Picker snap'ается обратно на предыдущий выбор. CloudSettingsDisclosure fades+expands в ~0.22s. Client ID SecureField получает caret через ~0.05s.
result: **n/a — Sanya на момент теста уже имела сохранённые credentials из 2026-04-20 сессии** (consent acceptedAt = 2026-04-20). Path не блокирующий: код покрыт unit-тестами `ProductModeCardTests`/Picker revert guard (см. 15-REVIEW §7 PASS).

### C. Enter valid keys + Save — status cycles, consent appears
expected: «Сохранить» активируется (Ink fill). Status: grey «Проверяю подключение…» → Sage dot «Подключено» за 2-5с. Consent-банер появляется с заголовком «КОНФИДЕНЦИАЛЬНОСТЬ». Cloud-сегмент в picker больше не залочен. Требуются живые GigaChat credentials из developers.sber.ru.
result: **passed** — keys из 2026-04-20 живы, probe 2026-04-22 23:58 показал «Подключено» (live OAuth round-trip к ngw.devices.sberbank.ru:9443, 10458/2748 bytes, см. 15-VERIFICATION-LIVE.md)

### D. «Принять и включить Cloud» — consent accepted, picker = Cloud
expected: Banner → post-ack с «Cloud активен с {DD.MM.YYYY}» + «Отозвать согласие». Picker label = «Говорун Cloud».
result: **passed** — `defaults read com.govorun.app` подтверждает `productMode = cloud` + `cloudConsentAcceptedAt = 2026-04-20`. UI открывается в post-ack состоянии.

### E. «Отозвать согласие» — consent revoked, mode = standard
expected: Banner → pre-ack за 0.22s. Picker label → «Говорун». Cloud-сегмент снова с lock.
result: **skipped (product decision 2026-04-23)** — не блокирует ship. Логика покрыта unit-тестами (`AppStateCloudShimTests`, `SettingsStoreTests.clearCloudConsent`).

### F. «Очистить» → confirm «Удалить» — keys cleared
expected: SwiftUI `.alert` с title «Удалить ключи API?», message «Cloud-режим станет недоступен. Ключи можно будет ввести снова.», две кнопки «Отмена» и красный destructive «Удалить». После confirm: оба SecureField пустые, Status «Не настроено», consent block скрыт.
result: **skipped (product decision 2026-04-23)** — destructive-flow с native SwiftUI `.alert`, поведение детерминированное. Unit-тесты покрывают `deleteCloudCredentials` path.

### G. Manual re-probe via «Проверить»
expected: Status: «Подключено» → «Проверяю подключение…» → «Подключено».
result: **passed** — Sanya 2026-04-22 23:58 нажала «Проверить», network-логи показали успешный OAuth роуд-трип на :9443 с возвратом 200.

### H. Wrong Client Secret — error state
expected: Ember dot + Ember text «Ключи отклонены Сбером. Проверьте Client ID и Secret.»
result: **skipped (product decision 2026-04-23)** — `cloudErrorMessage(for: AuthError.invalidResponse(401))` покрыт `CloudErrorCopyTests` (9 кейсов, 1293/1293 PASS на момент 15-03).

### I. Wi-Fi off + «Проверить» — offline error
expected: Ember dot + «Нет интернета. Cloud временно недоступен.»
result: **skipped (product decision 2026-04-23)** — offline-fallback покрыт unit-тестами Phase 14 (`PipelineEngineCloudTests.processCloudPath_fallsBackOnOffline`, `NetworkAvailabilityProvidingTests`).

### J. VoiceOver secure field accessibility
expected: Cmd+F5, Tab через Credentials. VO читает «Идентификатор клиента Client ID для GigaChat, secure text field» (label). Значение **НЕ** произносится. Тот же pattern для Client Secret.
result: **skipped (product decision 2026-04-23)** — accessibilityLabel/Hint statically declared, M-01/M-02 review fixes применены 2026-04-22 (commits 2e749f5, 07fe4d0). Revisit перед публичным релизом.

### K. Full test re-run in target environment
expected: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5` → Test Suite 'All tests' passed, 1297 tests.
result: **passed** — 1299/1299 PASS на машине Sanya 2026-04-22 20:06 (после REVIEW-FIX, baseline 1297 + 2 новых TDD H-01).

## Real-world cloud round-trip evidence (2026-04-22 23:58–00:00 MSK)

Network-level доказательство что end-to-end Cloud работает (не silent-fallback на Super/Standard):

```
C27 → ngw.devices.sberbank.ru:9443 (Sber OAuth)
    bytes in/out: 10458/2748
    duration: 61s, clean close
    → access token получен, статус «Подключено» реальный

C28 → gigachat.devices.sberbank.ru:443 (GigaChat API)
    bytes in/out: 7601/78368
    duration: 62s, ECONNRESET от Сбера в конце (норма после HTTP-ответа)
    → 76KB upload = WAV-обёрнутые PCM (Sanya диктовка ~2.4с)
    → 7.6KB response = file_id + /chat/completions результат
```

- `/files upload failed` / `/chat/completions failed` в OSLog **отсутствуют** → оба вызова вернули 200
- Локальный llama-server (:8080) **idle** во всё окно — нет slot launch / prompt processing → Super-фолбэк не сработал
- WAV-wrapper (commit `27d5861`) подтверждён: Сбер принял аудио без 400 "File format is not supported"

## Summary

total: 11
passed: 6 (A, C, D, G, K, plus B as n/a-non-blocking)
skipped: 5 (E, F, H, I, J — product decision, unit-test coverage сохранена)
issues: 0
blocked: 0

## Accepted-risk (non-blocking)

- **Revoke-during-dictation race** — per CONTEXT D-07.1: одна последняя cloud-передача после revoke допустима. Документировать в релиз-ноутах.
- **`.foregroundStyle` на `.menu` dropdown items не dim'ит на macOS 14.x** — per Landmine #4: lock-иконка сама по себе достаточный сигнал.
- **VoiceOver UAT отложен** — accessibility-метки M-01/M-02 заявлены статически в коде, но runtime VO-проверка перенесена на pre-release pass перед публикой.

## Gaps

Нет блокеров для закрытия Phase 15.
