# Requirements: Говорун Cloud

<!-- [skip-review: REQUIREMENTS.md checkbox flips при закрытии requirement — mechanical bookkeeping; содержательный Codex review уже был на spec phase, end-of-phase review покрывает cumulative diff per feedback_codex_reviews_artifacts.md] -->

**Defined:** 2026-04-11
**Core Value:** Cloud dictate через GigaChat-2-Max — audio-in, text-out за один API вызов с улучшенным качеством

## v2.0 Requirements

### Облачная инфраструктура (INFRA)

- [ ] **INFRA-01**: Сертификат Минцифры (SberRootCA.pem) вшит в приложение для TLS с Sber API
- [ ] **INFRA-02**: SberTrustPolicy реализует URLSessionDelegate для certificate pinning на `*.sberbank.ru`
- [ ] **INFRA-03**: CredentialStore хранит clientId и clientSecret в Keychain (Security.framework)
- [ ] **INFRA-04**: SberAuthService получает OAuth токен (scope GIGACHAT_API_PERS), кеширует с refresh margin, actor-based

### Облачный пайплайн (CLOUD)

- [ ] **CLOUD-01**: Аудио (WAV) загружается через `/api/v1/files` endpoint GigaChat API
- [ ] **CLOUD-02**: `/chat/completions` с attachment аудио + system prompt из SuperTextStyle.systemPrompt()
- [ ] **CLOUD-03**: GigaChat-2-Max обрабатывает аудио и возвращает нормализованный текст за один вызов
- [ ] **CLOUD-04**: Локальный STT (GigaAM) не используется в Cloud режиме
- [x] **CLOUD-05**: Сниппеты работают через матчинг trigger-слов на выходе LLM (SnippetEngine.match на output)
- [ ] **CLOUD-06**: Таймаут 30 секунд, retry с exponential backoff при 429/5xx

### Интеграция режимов (MODE)

- [ ] **MODE-01**: ProductMode.cloud — третий enum case рядом с standard и superMode
- [ ] **MODE-02**: Cloud маршрутизирует аудио в облако, минуя локальный STT и LLM
- [ ] **MODE-03**: Standard и Super режимы продолжают работать без изменений
- [ ] **MODE-04**: Cloud режим доступен только при наличии credentials в Keychain
- [x] **MODE-05**: ListFormatter и NormalizationGate работают с cloud output без изменений

### Настройки (UI)

- [ ] **UI-01**: Поля ввода clientId и clientSecret в настройках Cloud
- [ ] **UI-02**: Индикатор статуса подключения (не настроен / подключён / ошибка)
- [ ] **UI-03**: ProductMode picker с тремя вариантами (Говорун / Super / Cloud)
- [ ] **UI-04**: Privacy consent при первом включении Cloud (данные уходят на серверы Сбера)

### Тестирование (TEST)

- [ ] **TEST-01**: Unit-тесты для SberAuthService, CloudPipelineClient, CredentialStore через моки
- [ ] **TEST-02**: Benchmark качества cloud vs локальная модель на существующем seed

## Future Requirements

- Rewrite mode (выделение + голосовая инструкция «говорун, сделай деловым») — v3
- Generate mode (ключевое слово «говорун, напиши...») — v3
- Cloud STT fallback (SaluteSpeech) — отдельный проект
- Token usage display — после production launch
- Auto-fallback cloud → super при потере сети — UX risk, отложено

## Out of Scope

- Streaming responses — текст короткий, gain negligible
- B2B scope toggle — hardcode GIGACHAT_API_PERS
- New SPM dependencies — URLSession + Security.framework only
- Двухфазный API (транскрипция + нормализация) — один вызов audio-in достаточен
- Сниппеты через промпт — матчинг на выходе проще и надёжнее

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 10 | Pending |
| INFRA-02 | Phase 10 | Pending |
| INFRA-03 | Phase 10 | Pending |
| INFRA-04 | Phase 11 | Pending |
| CLOUD-01 | Phase 12 | Pending |
| CLOUD-02 | Phase 12 | Pending |
| CLOUD-03 | Phase 12 | Pending |
| CLOUD-04 | Phase 13 | Pending |
| CLOUD-05 | Phase 14 | Complete (14-04) |
| CLOUD-06 | Phase 12 | Pending |
| MODE-01 | Phase 13 | Pending |
| MODE-02 | Phase 13 | Pending |
| MODE-03 | Phase 13 | Pending |
| MODE-04 | Phase 13 | Pending |
| MODE-05 | Phase 14 | Complete (14-04) |
| UI-01 | Phase 15 | Pending |
| UI-02 | Phase 15 | Pending |
| UI-03 | Phase 15 | Pending |
| UI-04 | Phase 15 | Pending |
| TEST-01 | Phase 16 | Pending |
| TEST-02 | Phase 16 | Pending |
