# Roadmap: Говорун

<!-- [skip-review: ROADMAP.md progress flips are mechanical bookkeeping; Codex reviews spec + plan + end-of-phase diff per feedback_codex_reviews_artifacts.md] -->

## Milestones

- v1.0 Стили текста v2 (Phases 1-9) -- shipped 2026-04-02
- v2.0 Говорун Cloud (Phases 10-17) -- in progress

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v1.0 Стили текста v2 (Phases 1-9) -- SHIPPED 2026-04-02</summary>

- [x] **Phase 1: Foundation Types** - SuperTextStyle enum, LLMOutputContract, SuperStyleEngine с тестами
- [x] **Phase 2: Type Extraction** - Вынос SnippetPlaceholder, SnippetContext, NormalizationHints из TextMode.swift
- [x] **Phase 3: Pipeline Integration** - LLMClient новая сигнатура, PipelineEngine на SuperTextStyle, миграция тестов
- [x] **Phase 4: Gate Modernization** - Двухосевой evaluate, style-aware protected tokens, edit distance
- [x] **Phase 5: Postflight** - Стиль владеет точкой, applyDeterministic caps
- [x] **Phase 6: Settings & Data** - SettingsStore, HistoryStore, PipelineResult, UserDefaults миграция
- [x] **Phase 7: Analytics** - effective_style, style_selection_mode, product_mode в событиях
- [x] **Phase 8: UI** - Вкладка "Стиль текста" в menubar (авто/ручной, карточки, без модели)
- [x] **Phase 9: TextMode Deletion** - Удаление TextMode.swift, AppModeSettingsView, протоколов, очистка AppContextEngine

</details>

### v2.0 Говорун Cloud

- [x] **Phase 10: TLS & Credentials** - SberRootCA.pem, SberTrustPolicy, CredentialStore, HTTPClient protocol (completed 2026-04-12)
- [x] **Phase 11: OAuth** - SberAuthService с actor-based token coalescing, AuthError mapping (completed 2026-04-12)
- [x] **Phase 12: Cloud LLM Client** - CloudLLMClient conforming to LLMClient, audio-in pipeline, retry/timeout (completed 2026-04-12)
- [x] **Phase 13: Mode & Routing** - ProductMode.cloud, usesLLM audit, AppState wiring, PipelineEngine routing (completed 2026-04-12)
- [x] **Phase 14: Pipeline Hardening** - Snippet matching on LLM output, NormalizationGate passthrough, ListFormatter, offline fast-fail (completed 2026-04-19)
- [ ] **Phase 15: Cloud Settings UI** - Credential input, connection status, ProductMode picker, privacy consent
- [ ] **Phase 16: Tests** - Unit tests for all cloud services, quality benchmark cloud vs local
- [ ] **Phase 17: Polish & Rollout** - Error messages, analytics cloud events, credential-gated launch, edge cases

## Phase Details

### Phase 10: TLS & Credentials
**Goal**: App can establish trusted HTTPS connections to Sber domains and securely store API credentials
**Depends on**: Nothing (first phase of v2.0)
**Requirements**: INFRA-01, INFRA-02, INFRA-03
**Success Criteria** (what must be TRUE):
  1. SberRootCA.pem is bundled in the app and loadable at runtime via Security.framework
  2. A dedicated URLSession with SberTrustDelegate trusts `*.sberbank.ru` using the bundled CA while preserving system CA trust for all other domains
  3. CredentialStore saves and retrieves clientId + clientSecret from Keychain (Security.framework, not KeychainAccess)
  4. HTTPClient protocol exists with URLSession conformance, injectable for testing
**Plans:** 2/2 plans complete
Plans:
- [x] 10-01-PLAN.md -- SberRootCA.pem bundling + SberTrustPolicy with failable init, PEM parsing, SberTrustDelegate
- [x] 10-02-PLAN.md -- CredentialStore (Security.framework) + HTTPClient protocol with URLSession conformance

### Phase 11: OAuth
**Goal**: App can obtain and cache OAuth tokens from Sber API transparently
**Depends on**: Phase 10
**Requirements**: INFRA-04
**Success Criteria** (what must be TRUE):
  1. SberAuthService fetches OAuth token from `ngw.devices.sberbank.ru:9443/api/v2/oauth` with scope GIGACHAT_API_PERS
  2. Token is cached in memory and auto-refreshed 5 minutes before expiry (expires_at parsed as milliseconds)
  3. Concurrent token requests coalesce into a single HTTP call (actor-based, no thundering herd)
  4. RqUID header (UUID) is included in every OAuth request
  5. AuthError cases (credentialsNotFound, networkError, invalidResponse, tokenParsingFailed) map cleanly to LLMError at the client boundary
**Plans:** 1/1 plans complete
Plans:
- [x] 11-01-PLAN.md -- SberAuthService actor с OAuth, coalescing, AuthError (TDD)

### Phase 12: Cloud LLM Client
**Goal**: App can send audio to GigaChat API and receive normalized text back in a single round-trip
**Depends on**: Phase 11
**Requirements**: CLOUD-01, CLOUD-02, CLOUD-03, CLOUD-06
**Success Criteria** (what must be TRUE):
  1. CloudLLMClient conforms to LLMClient protocol without any protocol changes
  2. Audio WAV is uploaded via `/api/v1/files`, then `/chat/completions` is called with the file attachment and SuperTextStyle.systemPrompt()
  3. Response text is extracted from `choices[0].message.content`
  4. Timeout is 30 seconds; transient errors (429, 5xx) trigger one retry with exponential backoff
  5. CloudLLMConfiguration holds cloud-specific defaults (model: GigaChat-2-Max, temperature: 0.1, timeout: 30s)
**Plans:** 1/1 plans complete
Plans:
- [x] 12-01-PLAN.md -- CloudLLMClient с audio upload, chat/completions, retry, AuthError mapping (TDD)

### Phase 13: Mode & Routing
**Goal**: User can select Cloud as a third product mode and the pipeline routes audio through the cloud path
**Depends on**: Phase 12
**Requirements**: MODE-01, MODE-02, MODE-03, MODE-04, CLOUD-04
**Success Criteria** (what must be TRUE):
  1. ProductMode.cloud is a third enum case; `usesLLM` returns true for both super and cloud
  2. All 5 `usesLLM` guard sites in AppState are audited: cloud does not trigger llama-server start, model download, or LLMRuntimeManager
  3. AppState.applyProductMode(.cloud) wires CloudLLMClient into PipelineEngine via updateLLMClient()
  4. Cloud mode bypasses local STT and local LLM entirely -- audio goes directly to the cloud
  5. Standard and Super modes continue working identically to before (zero regression)
**Plans:** 2/2 plans complete
Plans:
- [x] 13-01-PLAN.md -- ProductMode.cloud enum + PipelineEngine cloud fork (TDD)
- [x] 13-02-PLAN.md -- AppState guard audit (usesLLM->usesLocalLLM) + cloud wiring + credential gate (TDD)

### Phase 14: Pipeline Hardening
**Goal**: Cloud output flows through the full post-processing pipeline correctly, including snippets and offline degradation
**Depends on**: Phase 13
**Requirements**: CLOUD-05, MODE-05
**Success Criteria** (what must be TRUE):
  1. SnippetEngine.match runs on CloudLLMClient output text (not rawTranscript), detecting trigger words in LLM-normalized text
  2. NormalizationGate evaluates cloud output with same contract/style logic as local LLM -- no special cloud thresholds needed initially (interpreted as: Gate код не модифицируется; cloud fork skips Gate per D-06/D-07)
  3. ListFormatter processes cloud output without changes
  4. When network is unavailable, cloud mode fast-fails (NetworkMonitor check) and degrades to deterministic text without 30s timeout wait
**Plans:** 4/4 plans complete
Plans:
- [x] 14-01-PLAN.md -- SnippetReinserter.cleanSubstitute helper для cloud embedded fallback (TDD)
- [x] 14-02-PLAN.md -- SuperTextStyle snippet-aware systemPrompt + NormalizationHints.snippetDictionary + CloudLLMClient wiring (TDD)
- [x] 14-03-PLAN.md -- NetworkAvailabilityProviding протокол + PipelineEngine DI (TDD)
- [x] 14-04-PLAN.md -- processCloudPath integration: offline fallback, dictionary, snippet, toast wiring

### Phase 15: Cloud Settings UI
**Goal**: User can enter credentials, see connection status, select Cloud mode, and give informed consent before data leaves the device
**Depends on**: Phase 13
**Requirements**: UI-01, UI-02, UI-03, UI-04
**Success Criteria** (what must be TRUE):
  1. Settings panel has fields for clientId and clientSecret that save to Keychain on input
  2. Connection status indicator shows one of: not configured / connected / error -- with actionable error text
  3. ProductMode picker shows three options (Говорун / Super / Cloud); Cloud is disabled when credentials are missing
  4. First time user enables Cloud mode, a privacy consent dialog explains that dictated audio/text will be sent to Sber GigaChat servers
**Plans:** 6 plans
Plans:
- [x] 15-01-PLAN.md -- SettingsStore.cloudConsentAcceptedAt accessor + clearCloudConsent (TDD, UI-04)
- [x] 15-02-PLAN.md -- AuthError.networkError preserves URLError + Equatable (TDD, Path B, UI-02)
- [ ] 15-03-PLAN.md -- cloudErrorMessage(for:) -> String в Views/CloudErrorCopy.swift (TDD, UI-02)
- [ ] 15-04-PLAN.md -- AppState shim: saveCloudCredentials / deleteCloudCredentials / probeCloudConnection (TDD, UI-01, UI-02)
- [x] 15-05-PLAN.md -- StatusDot 3-state (idle/connected/error) additive (UI-02)
- [ ] 15-06-PLAN.md -- CloudSettingsDisclosure.swift + ProductModeCard integration (UI-01, UI-02, UI-03, UI-04)
**UI hint**: yes

### Phase 16: Tests
**Goal**: All cloud services have comprehensive unit test coverage and cloud quality is benchmarked against local
**Depends on**: Phase 14, Phase 15
**Requirements**: TEST-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. SberAuthService, CloudLLMClient, CredentialStore each have mock-based unit tests covering happy path, error cases, and edge cases (token expiry, retry, keychain errors)
  2. SberTrustPolicy tested with MockTrustPolicy (not real certificates) -- no network calls in unit tests
  3. Quality benchmark compares cloud vs local normalization on existing eval seed, with results documented
**Plans**: TBD

### Phase 17: Polish & Rollout
**Goal**: Cloud mode is production-ready with clear error messages, analytics tracking, and safe launch behavior
**Depends on**: Phase 16
**Requirements**: CLOUD-06, MODE-04
**Success Criteria** (what must be TRUE):
  1. All cloud error states (auth failed, timeout, rate limit, server error) display actionable Russian-language messages in the bottom bar
  2. Analytics events include productMode: cloud, cloud_latency_ms, and normalization_source for cloud path
  3. On app launch with saved ProductMode.cloud but missing credentials, mode auto-downgrades to .standard (no crash, no dead state)
  4. Cloud dictation end-to-end works: hold key, speak, release, normalized text appears in active field via GigaChat-2-Max

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 10 -> 11 -> 12 -> 13 -> 14 -> 15 -> 16 -> 17

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 10. TLS & Credentials | v2.0 | 2/2 | Complete    | 2026-04-12 |
| 11. OAuth | v2.0 | 1/1 | Complete    | 2026-04-12 |
| 12. Cloud LLM Client | v2.0 | 1/1 | Complete   | 2026-04-12 |
| 13. Mode & Routing | v2.0 | 2/2 | Complete   | 2026-04-12 |
| 14. Pipeline Hardening | v2.0 | 3/4 | In progress | - |
| 15. Cloud Settings UI | v2.0 | 0/6 | Not started | - |
| 16. Tests | v2.0 | 0/? | Not started | - |
| 17. Polish & Rollout | v2.0 | 0/? | Not started | - |
