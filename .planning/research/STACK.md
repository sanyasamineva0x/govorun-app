# Technology Stack: GigaChat Max API Cloud Integration

**Project:** Govorun Cloud (v2.0)
**Researched:** 2026-04-06
**Overall confidence:** HIGH

## Executive Summary

The govorun-app already has the architectural scaffolding for cloud LLM integration: `LLMClient` protocol, `LLMError` enum, `NormalizationHints`, `SuperTextStyle` prompt generation. The prototype at `/govorun/` has a working `GigaChatClient` + `SberAuthService` + `SberTrustPolicy` + `CredentialStore`. The port path is straightforward: adapt the prototype code to govorun-app's conventions, using zero new third-party dependencies.

## Recommended Stack Additions

### HTTP Client: URLSession (no new dependencies)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| URLSession | Foundation (macOS 14+) | All HTTP requests to GigaChat API and Sber OAuth | Already used by LocalLLMClient; no new dependency needed |

**Decision: URLSession, not Alamofire/third-party.**

Rationale:
- govorun-app currently has exactly one SPM dependency (Sparkle). Adding a networking library for two HTTP endpoints (OAuth token + chat/completions) is unnecessary.
- The prototype already uses URLSession via the `HTTPClient` protocol. This protocol is already defined in the prototype's `SberAuthService.swift` and maps cleanly to `URLSession.data(for:)`.
- The existing `LocalLLMClient` in govorun-app already demonstrates the full pattern: URLRequest construction, JSON encoding/decoding, status code mapping, timeout handling.
- async/await `URLSession.data(for:)` is the project convention -- no completion handlers.

**Confidence: HIGH** -- validated by existing working code in both repos.

### OAuth 2.0 Token Management: Port SberAuthService

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SberAuthService (custom) | -- | OAuth 2.0 client_credentials flow for Sber API | Prototype has working implementation; 30-minute token cache with 5-min refresh margin |

**Token endpoint:** `https://ngw.devices.sberbank.ru:9443/api/v2/oauth`
**Scope for GigaChat:** `GIGACHAT_API_PERS`
**Auth method:** HTTP Basic (base64 of `clientId:clientSecret`)
**Token lifetime:** Sber returns `expires_at` as Unix ms timestamp; tokens typically last 30 minutes.

Key adaptations for govorun-app:
1. The prototype's `SberAuthService` uses `NSLock` for cached token -- matches govorun-app's concurrency pattern (NSLock, not actors, for `@unchecked Sendable` services).
2. The `HTTPClient` protocol from the prototype (`protocol HTTPClient: Sendable { func data(for:) }`) needs to be added to govorun-app. The prototype already has `extension URLSession: HTTPClient {}`.
3. The `credentialProvider` closure pattern is correct -- injects credential lookup without hard dependency on storage layer.
4. `RqUID` header (UUID per request) is required by Sber API -- prototype handles this correctly.

**What NOT to change:** Do not use a timer-based refresh. The prototype's lazy approach (check on each `getAccessToken()` call, refresh if within 5-min margin) is correct for a voice input app with bursty, infrequent API calls.

**Confidence: HIGH** -- prototype code runs in production against real Sber OAuth.

### Credential Storage: Apple Security.framework (Keychain direct)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Security.framework (Keychain) | macOS 14+ | Store clientId + clientSecret for GigaChat API | No third-party dependency; matches govorun-app's zero-dependency-for-core approach |

**Decision: Direct Keychain API, NOT KeychainAccess SPM package.**

The prototype's `/govorun/` repo uses `KeychainAccess` (kishikawakatsumi). Do NOT port this dependency to govorun-app. Reasons:

1. govorun-app stores exactly 2 strings (clientId, clientSecret). The Keychain API surface needed is: `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`. This is 4 functions.
2. Adding a third-party package for 4 function calls contradicts the project's minimal-dependency philosophy (currently only Sparkle).
3. A thin `KeychainWrapper` (30-40 lines) that wraps these 4 calls is trivially testable and avoids dependency risk.
4. The prototype's `CredentialStoring` protocol is the right abstraction -- port the protocol, replace the implementation.

Implementation pattern:
```swift
final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let service = "com.govorun.app.credentials"

    func saveLLMCredentials(clientId: String, clientSecret: String) throws {
        // SecItemAdd / SecItemUpdate with kSecClassGenericPassword
    }

    func getLLMCredentials() -> (clientId: String, secret: String)? {
        // SecItemCopyMatching
    }

    func deleteAll() throws {
        // SecItemDelete
    }
}
```

Key attributes: `kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount` (key name), `kSecValueData`.

**Confidence: HIGH** -- Apple's Keychain API is stable and well-documented. Pattern validated by hundreds of macOS apps.

### TLS Certificate Trust: Bundled Mintsifry Root CA

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Security.framework (SecTrust) | macOS 14+ | Trust Sber endpoints using Mintsifry root CA | Sber API uses Russian government CA not trusted by default on macOS |
| Bundled `SberRootCA.pem` | -- | Root CA certificate file | Must ship in app bundle; cannot rely on system trust store |

**This is critical.** Without the Mintsifry root CA, all HTTPS calls to `*.sberbank.ru` and `*.devices.sberbank.ru` will fail with certificate validation errors on macOS.

The prototype has a complete `SberTrustPolicy` implementation. Port requirements:

1. **Copy `SberRootCA.pem`** from `/govorun/Govorun/Resources/Certificates/` into govorun-app's Resources.
2. **Port the URLSessionDelegate** that adds bundled CA as additional trust anchor for Sber domains only.
3. **Simplify:** The prototype's `SberTrustPolicy` also handles gRPC TLS (for SaluteSpeech). govorun-app does NOT need gRPC -- strip `GRPC`/`NIOSSL`/`NIO` imports and the `grpcTLSConfiguration()` method entirely.
4. The `SberTrustPolicy.isSberDomain(_:)` helper is essential -- it scopes custom trust to `*.sberbank.ru` and `*.sber.ru` only, preserving default system trust for all other domains.
5. `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` is critical -- it trusts BOTH the bundled CA AND system CAs. Do not set to `true` or other HTTPS calls will break.

**Architecture note:** Create a dedicated `URLSession` instance with the `SberTrustDelegate` for all Sber API calls. Do NOT apply this delegate to `URLSession.shared` -- it would affect all HTTP calls in the app.

**Confidence: HIGH** -- prototype's implementation confirmed working; Sber developer docs explicitly require this.

### GigaChat API Client: Port GigaChatClient

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| CloudLLMClient (custom) | -- | Chat completions against GigaChat-2-Max API | Implements existing `LLMClient` protocol |

**API endpoint:** `https://gigachat.devices.sberbank.ru/api/v1/chat/completions`
**Model:** `GigaChat-2-Max` (second-generation; first-gen `GigaChat-Max` is deprecated and redirects)
**Temperature:** 0.1
**Request timeout:** 5 seconds
**Retry:** 1 retry with 500ms delay on rateLimited/serverError/timeout

Key adaptations for govorun-app:

1. **Rename to `CloudLLMClient`** (not `GigaChatClient`) -- follows PROJECT.md naming convention.
2. **Conform to existing `LLMClient` protocol:** `normalize(_:superStyle:hints:)` -- the prototype uses `normalize(_:mode:hints:)` with `TextMode`. Adapt to `SuperTextStyle`.
3. **Use Codable structs** for request/response (like `LocalLLMClient`) instead of `JSONSerialization` (prototype uses manual dict construction). This is testable, type-safe, matches govorun-app convention.
4. **Inject `URLSession`** via the `HTTPClient` protocol, NOT via the trust policy object. The `SberTrustPolicy` creates a pre-configured `URLSession` -- pass that session to the client.
5. **The prompt system works unchanged** -- `SuperTextStyle.systemPrompt(currentDate:personalDictionary:snippetContext:appName:)` already generates the correct system prompt for all three styles.

**Confidence: HIGH** -- prototype works, protocol boundary is clean.

### Error Handling: Extend Existing LLMError

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| LLMError (existing enum) | -- | Unified error type for both local and cloud LLM | Already covers networkError, invalidResponse, parsingFailed, rateLimited, serverError, timeout |

The existing `LLMError` enum needs exactly one addition:

```swift
case authenticationFailed  // OAuth token fetch failed or credentials missing
```

All other error cases (networkError, invalidResponse, parsingFailed, rateLimited, serverError, timeout) already cover the GigaChat API failure modes. Do NOT create a separate `CloudLLMError` -- the `NormalizationGate` and `PipelineEngine` already handle `LLMError`, and having two error types would require duplicating error handling everywhere.

For `AuthError` from the auth service, map it to `LLMError` at the `CloudLLMClient` boundary:
- `AuthError.credentialsNotFound` -> `LLMError.authenticationFailed`
- `AuthError.networkError` -> `LLMError.networkError`
- `AuthError.invalidResponse` -> `LLMError.authenticationFailed`
- `AuthError.tokenParsingFailed` -> `LLMError.authenticationFailed`

**Confidence: HIGH** -- existing error enum was designed to be extensible.

## Model Name: GigaChat-2-Max

| Model | Status | Scope | Notes |
|-------|--------|-------|-------|
| `GigaChat-2-Max` | Current | GIGACHAT_API_PERS | Second-generation flagship; use this |
| `GigaChat-Max` | Deprecated | GIGACHAT_API_PERS | Redirects to GigaChat-2-Max |
| `GigaChat-2-Pro` | Current | GIGACHAT_API_PERS | Cheaper alternative if needed |
| `GigaChat-2` | Current | GIGACHAT_API_PERS | Lite; insufficient for normalization quality |

The prototype uses `GigaChat-2` (lite). For production cloud mode, use `GigaChat-2-Max` -- the whole value proposition of Cloud mode is superior normalization quality over local GigaChat 3.1.

**Confidence: MEDIUM** -- model name from liteLLM docs and Go SDK constants; verify against actual `/models` endpoint response.

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| KeychainAccess SPM package | 2 strings to store; 4 Keychain API calls | Direct Security.framework wrapper (~35 lines) |
| Alamofire / async-http-client | 2 HTTP endpoints (OAuth + chat) | URLSession + HTTPClient protocol (already patterned) |
| grpc-swift | govorun-app is REST-only (no SaluteSpeech) | Not needed; prototype needed it for SaluteSpeech gRPC |
| swift-protobuf | Same -- no gRPC in govorun-app | Not needed |
| NIOSSL / SwiftNIO | Prototype used for gRPC TLS | Not needed; URLSession handles TLS |
| Network.framework (NWConnection) | Low-level; zero benefit over URLSession for REST | URLSession |
| Certificate pinning (hash-based) | Sber rotates certs; root CA trust anchoring is correct pattern | SberTrustDelegate with SecTrustSetAnchorCertificates |
| Separate error type for cloud | Would fork error handling in Pipeline/Gate | Extend existing LLMError |
| Separate prompt system | Cloud uses same normalization prompts | SuperTextStyle.systemPrompt works for both local and cloud |

## Files to Create (new)

| File | Layer | Purpose |
|------|-------|---------|
| `Services/CloudLLMClient.swift` | Services | GigaChat API client conforming to LLMClient |
| `Services/SberAuthService.swift` | Services | OAuth 2.0 token management |
| `Services/SberTrustPolicy.swift` | Services | Custom URLSession with Mintsifry CA trust |
| `Storage/KeychainCredentialStore.swift` | Storage | Keychain read/write for API credentials |
| `Resources/Certificates/SberRootCA.pem` | Resources | Bundled root CA certificate |

## Files to Modify (existing)

| File | Change |
|------|--------|
| `Services/LLMClient.swift` | Add `case authenticationFailed` to `LLMError` |
| `Models/ProductMode.swift` | Add `.cloud` case |
| `Storage/SettingsStore.swift` | Add cloud-related settings keys |
| `project.yml` | No new packages; add Certificates to copy phases |

## Integration Points

### PipelineEngine
Currently routes to `LocalLLMClient` when `ProductMode == .superMode`. Add routing:
- `.standard` -> DeterministicNormalizer only (unchanged)
- `.superMode` -> LocalLLMClient (unchanged)
- `.cloud` -> CloudLLMClient (new)

### NormalizationGate
Already works with any `LLMClient` output. The `.normalization` vs `.rewriting` contract is determined by `SuperTextStyle.contract`, not by the client type. Cloud mode reuses the same gate logic.

### AppState composition root
Wire new services:
```
SberTrustPolicy -> URLSession (custom trust)
KeychainCredentialStore -> credentialProvider closure
SberAuthService(credentialProvider:, scope:, httpClient:) -> authService
CloudLLMClient(authService:, httpClient:, baseURL:) -> cloudLLMClient
```

## Installation / project.yml Changes

```yaml
# No new packages needed. Only file additions:
# 1. Add SberRootCA.pem to Resources/Certificates/
# 2. project.yml copyFiles or sources already includes Govorun/ recursively
```

No `npm install`, no `swift package resolve` for new packages. The only build-time addition is copying `SberRootCA.pem` into the app bundle, which happens automatically since `sources: - path: Govorun` includes all subdirectories.

## Sources

- [GigaChat Go SDK constants (API URLs, scopes, model names)](https://github.com/paulrzcz/go-gigachat/blob/main/consts.go) -- HIGH confidence
- [GigaChat Python SDK (ai-forever/gigachat)](https://github.com/ai-forever/gigachat) -- HIGH confidence
- [Sber developer docs: Mintsifry certificates for GigaChat](https://developers.sber.ru/docs/ru/gigachat/certificates) -- HIGH confidence
- [Sber developer docs: TLS certificates](https://developers.sber.ru/docs/ru/sber-api/start/tls) -- HIGH confidence
- [Apple Keychain Services documentation](https://developer.apple.com/documentation/security/keychain-services) -- HIGH confidence
- [GigaChat API Postman collection](https://www.postman.com/salute-developers-7605/public/documentation/17b9yp0/gigachat-api) -- MEDIUM confidence
- [liteLLM GigaChat provider docs](https://docs.litellm.ai/docs/providers/gigachat) -- MEDIUM confidence
- Existing prototype: `/govorun/Govorun/Services/GigaChatClient.swift` -- HIGH confidence (production-tested)
- Existing prototype: `/govorun/Govorun/Services/SberAuthService.swift` -- HIGH confidence (production-tested)
- Existing prototype: `/govorun/Govorun/Services/SberTrustPolicy.swift` -- HIGH confidence (production-tested)

---
*Stack research for: GigaChat Max API cloud integration into govorun-app*
*Researched: 2026-04-06*
