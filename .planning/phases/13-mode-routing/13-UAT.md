---
status: partial
phase: 13-mode-routing
source:
  - 13-01-SUMMARY.md
  - 13-02-SUMMARY.md
started: 2026-04-14T15:35:00Z
updated: 2026-04-14T16:42:00Z
---

## Current Test

[testing paused — 1 item outstanding: cloud end-to-end blocked by Phase 15 UI]

## Tests

### 1. Cold start smoke test
expected: Свежая DMG собирается, устанавливается в /Applications, приложение запускается в menubar без крашей. Иконка Говоруна появляется в статусбаре, меню открывается по клику. Добавление третьего enum case ProductMode.cloud не сломало exhaustive switch нигде — компиляция прошла без ошибок, runtime-ассертов по switch нет.
result: pass

### 2. Стандартный режим — регрессия
expected: В .standard режиме (дефолт) зажимаешь активационную клавишу, диктуешь фразу в Mail/Notes/Telegram, отпускаешь — текст вставляется через deterministic-нормализацию (caps, точки, бренды, сниппеты). Никаких обращений к llama-server или CloudLLMClient, никакой задержки LLM. Нулевая регрессия относительно v1.0.
result: pass

### 3. Говорун Super — регрессия
expected: Переключаешься на .superMode в настройках. llama-server стартует, модель грузится, статус ready. Зажимаешь клавишу, диктуешь, отпускаешь — текст нормализуется через LocalLLMClient + NormalizationGate и вставляется в активное поле. Никаких cloud-обращений. Поведение идентично тому, как было до Phase 13.
result: pass

### 4. Полный xctest suite
expected: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` проходит все 1245+ тестов без failures, включая новые 40 тестов Phase 13 (14 ProductModeTests + 10 PipelineEngineTests cloud + 16 IntegrationTests guard audit + cloud wiring).
result: pass
verified_by: "Claude ran xcodebuild test — 1245 executed, 0 failures, TEST SUCCEEDED in 57.9s (2026-04-14T19:15Z)"

### 5. Cloud path end-to-end (optional)
expected: Через dev-инжекцию (`defaults write com.govorun.app productMode cloud` + SberCredentials в Keychain через CredentialStore) productMode становится .cloud. После рестарта приложения auto-downgrade не срабатывает (credentials есть), PipelineEngine уходит в cloud fork при диктовке, audio улетает в GigaChat Max, нормализованный ответ вставляется в активное поле. Если нет желания настраивать вручную — отметить blocked (до Phase 15 UI).
result: blocked
blocked_by: prior-phase
reason: "Deferred to Phase 15 UI (Cloud Settings UI). User chose not to set up manual dev-injection (defaults write + Keychain) for one-off verification. Real UAT path is through the Phase 15 credential UI + ProductMode picker, which doesn't exist yet. Phase 13 unit coverage (40 tests across ProductMode/Pipeline/Integration) covers the routing logic exhaustively — this test was optional stretch."

## Summary

total: 5
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 1

## Gaps

[none yet]
