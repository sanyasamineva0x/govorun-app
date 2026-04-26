# Feature Landscape: Cloud Mode (GigaChat Max API)

**Domain:** Cloud LLM normalization mode for macOS speech-to-text app
**Researched:** 2026-04-06
**Confidence:** HIGH (prototype code reviewed, GigaChat API docs verified)

## Context

Existing app has two modes: Govorun (deterministic) and Govorun Super (local LLM via llama-server). This milestone adds a third: Govorun Cloud (GigaChat Max API). A working prototype exists in the separate `govorun` repo with `GigaChatClient`, `SberAuthService`, `SberTrustPolicy`, and `CredentialStore` -- these must be ported and adapted to the govorun-app codebase.

---

## Table Stakes

Features users expect from any cloud LLM mode. Missing any of these makes Cloud mode feel broken or untrustworthy.

| Feature | Why Expected | Complexity | Depends On |
|---------|--------------|------------|------------|
| **CloudLLMClient (HTTP)** | Core integration -- sends text to GigaChat API, receives normalized output | MEDIUM | SberAuthService, SberTrustPolicy |
| **SberAuthService (OAuth)** | GigaChat requires OAuth token via `POST /api/v2/oauth` with Basic auth (Base64 of clientId:clientSecret). Token TTL 30 min, auto-refresh 5 min before expiry | MEDIUM | CredentialStore |
| **SberTrustPolicy (custom TLS)** | Sber API uses Russian Trusted Root CA (MinTsifry), not in standard CA bundles. URLSession needs custom `SecTrust` delegate pinning `SberRootCA.pem` | MEDIUM | SberRootCA.pem certificate in bundle |
| **Keychain credential storage** | `clientId` + `clientSecret` in Keychain via `CredentialStore`. Never UserDefaults, never hardcoded | LOW | Existing CredentialStore pattern; adapt from prototype `com.govorun.llm.*` keys |
| **ProductMode.cloud** | Third enum case in `ProductMode`. `usesLLM` returns true. Pipeline routes to CloudLLMClient instead of LocalLLMClient | LOW | ProductMode enum, PipelineEngine |
| **Cloud settings UI** | Input fields for clientId + clientSecret, connection status indicator, "Test connection" button | MEDIUM | SettingsStore, CredentialStore |
| **Connection status indicator** | User must see at a glance: configured / connecting / connected / error. Menubar or settings panel | LOW | SberAuthService state |
| **Graceful error states** | Network timeout, auth failure (401), rate limit (429), server error (5xx) -- all must show actionable user-facing messages, never raw errors | MEDIUM | LLMError enum (already has cases, needs cloud-specific messages) |
| **Offline fallback to deterministic** | When cloud is unreachable, fall back to deterministic normalization (same as Super mode LLM failure path). Never block the user | LOW | PipelineEngine already has `.llmFailed` path |
| **NormalizationGate integration** | Cloud LLM output must pass through the same Gate as local LLM. Same contract/style logic, same edit distance checks | LOW | NormalizationGate, LLMOutputContract (already exist) |
| **Style support (relaxed/normal/formal)** | Cloud mode must respect SuperTextStyle -- same systemPrompt logic, same auto/manual style engine | LOW | SuperTextStyle.systemPrompt() (already exists), SuperStyleEngine |
| **Retry with backoff** | Single retry on transient errors (429, 500-504, timeout) with 0.5s delay. Prototype already implements this | LOW | GigaChatClient prototype has retry logic |

### Table Stakes Rationale

The prototype in `govorun` repo already implements most of these. The primary work is porting + adapting to govorun-app's evolved interfaces (SuperTextStyle replaced TextMode, NormalizationGate has two-axis contract logic, LLMClient signature changed).

---

## Differentiators

Features that make Cloud mode valuable over just using Super mode. These justify the cloud dependency.

| Feature | Value Proposition | Complexity | Depends On |
|---------|-------------------|------------|------------|
| **Superior normalization quality** | GigaChat Max (128K context, 8K output) vs local GigaChat 3.1 10B Q4_K_M. Cloud model is full-precision, larger, better at Russian grammar/punctuation/style nuance | FREE | CloudLLMClient (same prompt, better model) |
| **No local model download (6GB)** | Cloud mode works immediately after entering credentials. No 6GB GGUF download, no ~8GB RAM overhead | FREE | Architecture decision |
| **No llama-server dependency** | No static binary build, no runtime process management, no healthchecks. Just HTTP | FREE | Architecture decision |
| **Token usage tracking** | Show user how many tokens consumed per request and cumulative. GigaChat API returns `usage.prompt_tokens` + `usage.completion_tokens` in response | LOW | CloudLLMClient response parsing |
| **Faster response on good network** | Cloud API typically responds in 1-3s for normalization-length prompts vs local llama-server cold start + inference. Especially on machines where RAM is tight | FREE | Network quality dependent |
| **Model version pinning** | Specify `GigaChat-Max` explicitly. When Sber upgrades, user benefits automatically without app update | FREE | `model` parameter in API request |
| **Scope-based access control** | `GIGACHAT_API_PERS` for individuals (free tier), `GIGACHAT_API_B2B` for business. User selects scope in settings | LOW | SberAuthService scope parameter |

### Key Differentiator: Quality

The primary value proposition of Cloud mode is normalization quality. GigaChat Max API runs a full-precision model (not quantized Q4_K_M) with 128K context window. For Russian text normalization -- especially formal style with morphological ты/вы, brand casing, and complex punctuation -- cloud quality will be measurably better. This should be validated with the eval framework (GovorunEval.xctestplan) once the client is integrated.

---

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature | Why It Seems Useful | Why Avoid | What to Do Instead |
|--------------|---------------------|-----------|-------------------|
| **Streaming responses** | Lower perceived latency | Normalization is short text (<128 tokens output). Streaming adds complexity (SSE parsing, partial display) for negligible UX gain. Prototype uses non-streaming | Non-streaming POST, show spinner during request |
| **Proxy server for auth** | Avoid exposing clientId/Secret | Adds server infra to a desktop app. OAuth under the hood is transparent enough. User manages their own Sber credentials | Direct OAuth from client, credentials in Keychain |
| **Auto-fallback to Super mode** | Seamless degradation | Confusing UX -- user chose Cloud explicitly. Silent mode switch hides connection problems. Better to show clear error and fall back to deterministic only | Fall back to deterministic (existing `.llmFailed` path). Show status indicator so user knows |
| **Cloud STT (SaluteSpeech)** | Full cloud pipeline | Explicitly out of scope per PROJECT.md. Separate project | Keep offline GigaAM STT, only LLM normalization is cloud |
| **Token budget / spending limits** | Cost control | Premature for 2M test tokens. Adds complexity (persistent counter, reset logic, warning thresholds) | Show per-request usage. Add budget controls later if needed |
| **Multiple cloud providers** | Flexibility | Only one provider (GigaChat). Abstracting for hypothetical providers adds indirection | CloudLLMClient is concrete. LLMClient protocol already provides the abstraction layer |
| **Rewrite mode / Generate mode** | Power features | Explicitly out of scope per PROJECT.md (v2 scope) | Keep pipeline as dictate-only for this milestone |
| **Per-request model selection** | Use Pro for cheap, Max for quality | Premature optimization. Start with Max, evaluate cost later | Hardcode `GigaChat-Max` model |
| **Credential sync across devices** | Convenience | Desktop-only app, no iCloud entitlement, single-machine usage pattern | Manual credential entry per machine |

---

## Feature Dependencies

```
CredentialStore (Keychain)
    |
    v
SberAuthService (OAuth token management)
    |       |
    v       v
SberTrustPolicy (TLS with Russian Root CA)
    |
    v
CloudLLMClient (HTTP client implementing LLMClient protocol)
    |
    v
ProductMode.cloud (new enum case)
    |       |
    v       v
PipelineEngine routing          SettingsStore (productMode, credentials)
    |                               |
    v                               v
NormalizationGate               Cloud Settings UI
(existing, no changes)          (credential input, status, scope)
```

### Critical Path

1. **SberRootCA.pem** must be bundled -- without it, all HTTPS to Sber domains fails
2. **CredentialStore** must have LLM-specific keys (prototype already has `com.govorun.llm.*`)
3. **SberAuthService** depends on CredentialStore + SberTrustPolicy
4. **CloudLLMClient** depends on SberAuthService
5. **ProductMode.cloud** and PipelineEngine routing depend on CloudLLMClient
6. **UI** depends on all of the above for testing/status display

### Integration Points with Existing Code

| Existing Component | Change Required | Risk |
|--------------------|-----------------|------|
| `LLMClient` protocol | None -- CloudLLMClient conforms to existing `normalize(_:superStyle:hints:)` | LOW |
| `LLMError` enum | May need cloud-specific cases (e.g., `.authFailed`, `.credentialsNotFound`) or keep using existing cases with descriptive messages | LOW |
| `ProductMode` enum | Add `.cloud` case, update `usesLLM`, `title`, `subtitle` | LOW (additive) |
| `PipelineEngine` | None -- already uses `LLMClient` protocol, `productMode.usesLLM` drives routing | LOW |
| `NormalizationGate` | None -- works on text, agnostic to LLM source | NONE |
| `SuperTextStyle` | None -- prompts already parameterized, work with any LLM | NONE |
| `SettingsStore` | Add cloud credential fields, scope, persist productMode.cloud | LOW |
| `AppState` | Add CloudLLMClient initialization, mode switching logic, connection state wiring | MEDIUM |
| `AppState.applyProductMode()` | Must handle three modes now (standard, super, cloud). Cloud doesn't need llama-server or model assets | MEDIUM |

---

## GigaChat API Specifics (Ported from Prototype)

### Authentication Flow
1. User enters `clientId` + `clientSecret` in Settings
2. Stored in Keychain via `CredentialStore` (keys `com.govorun.llm.clientId`, `com.govorun.llm.clientSecret`)
3. `SberAuthService` encodes `clientId:clientSecret` as Base64 for Basic auth
4. POST to `https://ngw.devices.sberbank.ru:9443/api/v2/oauth` with `scope=GIGACHAT_API_PERS`
5. Response: `{ "access_token": "...", "expires_at": 1234567890000 }` (ms timestamp)
6. Token cached in memory, refreshed 5 min before expiry
7. On 401 during API call, refresh token and retry once

### API Call Flow
1. POST to `https://gigachat.devices.sberbank.ru/api/v1/chat/completions`
2. Headers: `Authorization: Bearer <token>`, `Content-Type: application/json`
3. Body: `{ "model": "GigaChat-Max", "temperature": 0.1, "messages": [...] }`
4. Response includes `choices[0].message.content` + `usage` object
5. Timeout: 5s (prototype default), retry once on 429/5xx/timeout with 0.5s delay

### TLS Requirement
- Sber endpoints use certificates from Russian Ministry of Digital Development
- Not in standard macOS trust store
- Solution: Bundle `SberRootCA.pem`, create custom `URLSessionDelegate` that adds it as anchor certificate for `*.sberbank.ru` domains
- Already implemented in prototype as `SberTrustPolicy`

---

## Complexity Assessment

| Component | Lines of Code (est.) | Test Count (est.) | Risk |
|-----------|---------------------|-------------------|------|
| SberTrustPolicy (port) | ~80 | ~10 | LOW -- proven in prototype |
| CredentialStore LLM keys (port) | ~30 | ~8 | LOW -- pattern exists |
| SberAuthService (port + adapt) | ~120 | ~20 | MEDIUM -- OAuth edge cases |
| CloudLLMClient (new, based on prototype) | ~150 | ~25 | MEDIUM -- new LLMClient signature |
| ProductMode.cloud | ~20 | ~10 | LOW -- additive enum case |
| PipelineEngine routing | ~10 | ~5 | LOW -- protocol-based, minimal changes |
| SettingsStore cloud fields | ~40 | ~10 | LOW |
| Cloud Settings UI | ~200 | ~5 | MEDIUM -- new SwiftUI views |
| AppState cloud wiring | ~80 | ~15 | MEDIUM -- mode switching complexity |
| **Total** | **~730** | **~108** | |

---

## MVP Recommendation

### Launch With (P0)

1. **CredentialStore LLM keys** -- port from prototype, adapt to govorun-app Keychain patterns
2. **SberRootCA.pem in bundle** -- copy from prototype
3. **SberTrustPolicy** -- port from prototype (remove gRPC/NIO dependencies, keep URLSession delegate only)
4. **SberAuthService** -- port from prototype, adapt credential provider to new CredentialStore
5. **CloudLLMClient** -- new implementation conforming to `LLMClient` protocol with `normalize(_:superStyle:hints:)` signature
6. **ProductMode.cloud** -- add enum case with proper properties
7. **PipelineEngine + AppState routing** -- wire cloud client when mode is `.cloud`
8. **Cloud Settings UI** -- credential input, connection test, status indicator
9. **Analytics** -- track `productMode: cloud`, cloud latency, token usage

### Launch With (P1)

10. **Token usage display** -- show prompt/completion tokens per request in history
11. **Scope selection** -- PERS vs B2B toggle in settings (default PERS)

### Defer to Next Milestone

- Token budget / spending limits
- Streaming responses
- Auto-fallback to Super mode
- Cloud STT
- Rewrite / Generate modes

---

## Sources

- [GigaChat REST API Documentation](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/gigachat-api)
- [GigaChat Python SDK (reference implementation)](https://github.com/ai-forever/gigachat)
- [GigaChat API Integration Guide](https://developers.sber.ru/docs/ru/gigachat/api/integration)
- [GigaChat OAuth Token Endpoint](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-token)
- [GigaChat 2 Max Specs](https://cloudprice.net/models/gigachat/GigaChat-2-Max) -- 128K context, 8K output
- Prototype code: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/GigaChatClient.swift`
- Prototype code: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/SberAuthService.swift`
- Prototype code: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/SberTrustPolicy.swift`
- Prototype code: `/Users/sanyasamineva/Desktop/govorun/Govorun/Storage/CredentialStore.swift`

---
*Feature research for: Cloud LLM mode (GigaChat Max API) -- Govorun v2.0*
*Researched: 2026-04-06*
