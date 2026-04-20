---
status: partial
phase: 15-cloud-settings-ui
source: [15-VERIFICATION.md, 15-06-SUMMARY.md §UAT Checkpoint]
started: 2026-04-20T20:45:00+03:00
updated: 2026-04-20T20:45:00+03:00
---

## Current Test

[awaiting human testing]

## Pre-requisites

1. Получить Sber GigaChat API ключи из https://developers.sber.ru/studio/workspaces/
2. Собрать DMG и установить:
   ```bash
   pkill -f Govorun 2>/dev/null; sleep 1
   bash scripts/build-unsigned-dmg.sh 2>&1 | grep 'готов'
   rm -rf /Applications/Govorun.app
   hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null
   MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}')
   cp -R "$MOUNT/Govorun.app" /Applications/
   hdiutil detach "$MOUNT" 2>/dev/null
   xattr -cr /Applications/Govorun.app
   open /Applications/Govorun.app
   ```
3. Разрешить Accessibility при запросе.

## Tests

### A. Picker dropdown lock icon + opacity
expected: Settings → Main, dropdown picker: три пункта. У «Говорун Cloud» есть `lock.fill` после текста + Ink 0.25 opacity (dimmed). Accept-risk per Landmine #4 — если opacity не применяется под `.menu` pickerStyle, icon сам по себе достаточный сигнал.
result: [pending]

### B. Click Cloud without credentials — revert + disclosure + focus
expected: Picker snap'ается обратно на предыдущий выбор. CloudSettingsDisclosure fades+expands в ~0.22s. Client ID SecureField получает caret через ~0.05s.
result: [pending]

### C. Enter valid keys + Save — status cycles, consent appears
expected: «Сохранить» активируется (Ink fill). Status: grey «Проверяю подключение…» → Sage dot «Подключено» за 2-5с. Consent-банер появляется с заголовком «КОНФИДЕНЦИАЛЬНОСТЬ». Cloud-сегмент в picker больше не залочен. Требуются живые GigaChat credentials из developers.sber.ru.
result: [pending]

### D. «Принять и включить Cloud» — consent accepted, picker = Cloud
expected: Banner → post-ack с «Cloud активен с {DD.MM.YYYY}» + «Отозвать согласие». Picker label = «Говорун Cloud».
result: [pending]

### E. «Отозвать согласие» — consent revoked, mode = standard
expected: Banner → pre-ack за 0.22s. Picker label → «Говорун». Cloud-сегмент снова с lock.
result: [pending]

### F. «Очистить» → confirm «Удалить» — keys cleared
expected: SwiftUI `.alert` с title «Удалить ключи API?», message «Cloud-режим станет недоступен. Ключи можно будет ввести снова.», две кнопки «Отмена» и красный destructive «Удалить». После confirm: оба SecureField пустые, Status «Не настроено», consent block скрыт.
result: [pending]

### G. Manual re-probe via «Проверить»
expected: Status: «Подключено» → «Проверяю подключение…» → «Подключено».
result: [pending]

### H. Wrong Client Secret — error state
expected: Ember dot + Ember text «Ключи отклонены Сбером. Проверьте Client ID и Secret.»
result: [pending]

### I. Wi-Fi off + «Проверить» — offline error
expected: Ember dot + «Нет интернета. Cloud временно недоступен.»
result: [pending]

### J. VoiceOver secure field accessibility
expected: Cmd+F5, Tab через Credentials. VO читает «Идентификатор клиента Client ID для GigaChat, secure text field» (label). Значение **НЕ** произносится. Тот же pattern для Client Secret.
result: [pending]

### K. Full test re-run in target environment
expected: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5` → Test Suite 'All tests' passed, 1297 tests. Уже верифицировано автоматом в CI-подобном окружении; step K — финальный sanity check на машине Sanya.
result: [pending]

## Summary

total: 11
passed: 0
issues: 0
pending: 11
skipped: 0
blocked: 0

## Accepted-risk (non-blocking)

- **Revoke-during-dictation race** — per CONTEXT D-07.1: одна последняя cloud-передача после revoke допустима. Документировать в релиз-ноутах.
- **`.foregroundStyle` на `.menu` dropdown items не dim'ит на macOS 14.x** — per Landmine #4: lock-иконка сама по себе достаточный сигнал.

## Gaps
