# Phase 12: Cloud LLM Client - Research

**Researched:** 2026-04-12
**Domain:** GigaChat REST API client (file upload + chat/completions with audio attachment), Swift URLSession
**Confidence:** HIGH

## Summary

Phase 12 builds `CloudLLMClient` -- an HTTP client that uploads WAV audio to GigaChat API via `/api/v1/files`, then calls `/chat/completions` with the file attachment and system prompt from `SuperTextStyle.systemPrompt()`. The client conforms to the existing `LLMClient` protocol (for text path) and adds a `processAudio` method for the cloud audio-in path.

The codebase already has all infrastructure: `HTTPClient` protocol with `MockHTTPClient`, `SberAuthService` (actor-based OAuth with token caching), `SberTrustPolicy` (certificate pinning URLSession), `LLMError` enum with all needed cases, and `LocalLLMClient` as a structural reference. The prototype `GigaChatClient` from the original project provides portable retry, error handling, and response parsing logic. The GigaChat Python SDK source code (inspected from `ai-forever/gigachat` repo) confirms the exact API contract for file upload and chat/completions with attachments.

**Primary recommendation:** Port prototype `GigaChatClient` patterns (sendRequest, parseResponse, isRetryable) into a new `CloudLLMClient` class. Build multipart WAV upload from scratch using standard URLSession (no third-party dependencies). Use `JSONSerialization` for request/response (consistent with prototype, not Codable structs).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** CloudLLMClient has two public methods: `normalize(text:superStyle:hints:)` (LLMClient conformance) and `processAudio(audioData:superStyle:hints:)` (Cloud audio-in path). Both share internal auth, error handling, response parsing logic.
- **D-02:** Phase 13 (routing) calls `processAudio` directly, bypassing LLMClient interface. Protocol for audio path (if needed for DI) is Phase 13 responsibility, not Phase 12.
- **D-03:** LLMClient protocol does NOT change. CloudLLMClient conforms as-is.
- **D-04:** `final class CloudLLMClient: LLMClient, @unchecked Sendable`. All dependencies via `let` in init (authService, httpClient, configuration). No mutable state, no NSLock needed. Consistent with LocalLLMClient.
- **D-05:** Two-step flow: (1) upload WAV -> file ID, (2) chat/completions with file ID. On error at step 2 (429/5xx) -- retry only completions, file ID is reused. On error at step 1 (upload) -- error immediately, no retry.
- **D-06:** One retry with exponential backoff (as in success criteria). SberAuthService refreshes token automatically -- expired token between steps not a problem.
- **D-07:** AuthError -> LLMError mapping inside CloudLLMClient (Phase 11, D-01). credentialsNotFound -> networkError, AuthError.networkError -> LLMError.networkError, invalidResponse -> invalidResponse, tokenParsingFailed -> parsingFailed.

### Claude's Discretion
- CloudLLMConfiguration shape and defaults (model: GigaChat-2-Max, temperature: 0.1, timeout: 30s from ROADMAP)
- Internal structure: upload/completions as private methods
- isRetryable extension on LLMError (port from prototype)
- Multipart form-data format for WAV upload
- Naming: processAudio vs processAudioData vs other

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLOUD-01 | Audio (WAV) uploaded via `/api/v1/files` endpoint of GigaChat API | GigaChat SDK source confirms POST `/files` with multipart/form-data, `purpose: "general"`. Response: `UploadedFile` with `id` field. |
| CLOUD-02 | `/chat/completions` with audio attachment + system prompt from `SuperTextStyle.systemPrompt()` | SDK confirms `Messages.attachments: Optional[List[str]]` -- list of file IDs. System prompt generation already exists in `SuperTextStyle.systemPrompt()`. |
| CLOUD-03 | GigaChat-2-Max processes audio and returns normalized text in one call | SDK settings confirm base URL `https://gigachat.devices.sberbank.ru/api/v1`. Model name `GigaChat-2-Max` from ROADMAP. Response: `choices[0].message.content`. |
| CLOUD-06 | 30s timeout, retry with exponential backoff on 429/5xx | SDK settings confirm default timeout 30s, retry codes `(429, 500, 502, 503, 504)`, backoff factor 0.5. Prototype has `isRetryable` extension. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation/URLSession | system | HTTP client, multipart upload | Project constraint: no new SPM dependencies [VERIFIED: REQUIREMENTS.md Out of Scope] |
| JSONSerialization | system | Request/response JSON | Consistent with prototype GigaChatClient pattern [VERIFIED: prototype source] |
| OSLog | system | Structured logging | Project convention: Logger(subsystem:category:) [VERIFIED: CLAUDE.md] |

### Supporting (existing, already in project)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| HTTPClient protocol | existing | DI for URLSession | Inject `SberTrustPolicy.urlSession` via HTTPClient [VERIFIED: Govorun/Services/HTTPClient.swift] |
| SberAuthService | existing | OAuth token | `getAccessToken()` returns Bearer token [VERIFIED: Govorun/Services/SberAuthService.swift] |
| LLMError enum | existing | Typed errors | All needed cases already present [VERIFIED: Govorun/Services/LLMClient.swift] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSONSerialization | Codable structs | Prototype uses JSONSerialization; Codable adds boilerplate for simple payloads. Stay consistent with prototype. |
| Manual multipart | Third-party (Alamofire) | Project forbids new SPM deps. URLSession multipart is ~30 lines of code. |

**Installation:** No installation needed -- all system frameworks.

## Architecture Patterns

### Recommended Project Structure
```
Govorun/Services/
    CloudLLMClient.swift       # CloudLLMClient class + CloudLLMConfiguration struct
    LLMClient.swift            # Existing -- no changes (LLMClient protocol, LLMError, LocalLLMConfiguration)
    HTTPClient.swift           # Existing -- no changes
    SberAuthService.swift      # Existing -- no changes
GovorunTests/
    CloudLLMClientTests.swift  # Tests using MockHTTPClient + MockAuthService
```

### Pattern 1: Two-Step Audio Processing
**What:** Upload WAV to get file ID, then call chat/completions with that file ID as attachment.
**When to use:** Every `processAudio` call.
**Example:**
```swift
// Source: GigaChat Python SDK (ai-forever/gigachat, api/files.py + models/chat.py)
// Step 1: POST /files (multipart/form-data)
// Request: file=<WAV data>, purpose="general"
// Response: {"id": "file-uuid", "bytes": 12345, "created_at": 1234567890, "filename": "audio.wav", "purpose": "general"}

// Step 2: POST /chat/completions
// Request body:
// {
//   "model": "GigaChat-2-Max",
//   "temperature": 0.1,
//   "messages": [
//     {"role": "system", "content": "<system prompt>"},
//     {"role": "user", "content": "", "attachments": ["<file-id>"]}
//   ]
// }
// Response: {"choices": [{"message": {"content": "normalized text"}}], ...}
```

### Pattern 2: Retry Only Completions (D-05)
**What:** If completions fails with retryable error, retry only the completions call, reusing file ID.
**When to use:** On 429 or 5xx from chat/completions.
**Example:**
```swift
// Source: Prototype GigaChatClient (govorun/Services/GigaChatClient.swift)
// Port isRetryable pattern:
extension LLMError {
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout:
            return true
        default:
            return false
        }
    }
}

// In processAudio:
// let fileID = try await uploadAudio(audioData, token: token)
// do {
//     return try await sendChatCompletion(fileID: fileID, ...)
// } catch let error as LLMError where error.isRetryable {
//     try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
//     return try await sendChatCompletion(fileID: fileID, ...)
// }
```

### Pattern 3: AuthError -> LLMError Mapping (D-07)
**What:** Map auth layer errors to LLM layer errors at the CloudLLMClient boundary.
**When to use:** Every call that acquires a token.
**Example:**
```swift
// Source: CONTEXT.md D-07
private func mapAuthError(_ error: AuthError) -> LLMError {
    switch error {
    case .credentialsNotFound:
        return .networkError("Cloud credentials not configured")
    case .networkError(let message):
        return .networkError(message)
    case .invalidResponse(let statusCode):
        return .invalidResponse(statusCode: statusCode)
    case .tokenParsingFailed:
        return .parsingFailed
    }
}
```

### Pattern 4: Multipart Form-Data for WAV Upload
**What:** Construct multipart/form-data body with WAV audio data and purpose field.
**When to use:** POST /files endpoint.
**Example:**
```swift
// Source: Standard URLSession multipart pattern (swiftbysundell.com/articles/http-post-and-file-upload-requests-using-urlsession)
private func buildMultipartBody(audioData: Data, boundary: String) -> Data {
    var body = Data()
    // purpose field
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
    body.append("general\r\n")
    // file field
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
    body.append("Content-Type: audio/wav\r\n\r\n")
    body.append(audioData)
    body.append("\r\n")
    body.append("--\(boundary)--\r\n")
    return body
}
```

### Pattern 5: CloudLLMConfiguration (parallel to LocalLLMConfiguration)
**What:** Static defaults struct with configuration values for cloud client.
**When to use:** CloudLLMClient init.
**Example:**
```swift
// Source: Govorun/Services/LLMClient.swift LocalLLMConfiguration pattern
struct CloudLLMConfiguration: Equatable {
    static let defaultBaseURLString = "https://gigachat.devices.sberbank.ru/api/v1"
    static let defaultModel = "GigaChat-2-Max"
    static let defaultTemperature = 0.1
    static let defaultRequestTimeout: TimeInterval = 30.0
    static let defaultRetryDelay: TimeInterval = 0.5
    static let defaultMaxOutputTokens = 128

    let baseURLString: String
    let model: String
    let temperature: Double
    let requestTimeout: TimeInterval
    let retryDelay: TimeInterval
    let maxOutputTokens: Int

    init(
        baseURLString: String = defaultBaseURLString,
        model: String = defaultModel,
        temperature: Double = defaultTemperature,
        requestTimeout: TimeInterval = defaultRequestTimeout,
        retryDelay: TimeInterval = defaultRetryDelay,
        maxOutputTokens: Int = defaultMaxOutputTokens
    ) {
        self.baseURLString = baseURLString
        self.model = model
        self.temperature = temperature
        self.requestTimeout = max(0.1, requestTimeout)
        self.retryDelay = max(0, retryDelay)
        self.maxOutputTokens = max(1, maxOutputTokens)
    }
}
```

### Anti-Patterns to Avoid
- **Do NOT use Codable for request body:** Prototype uses `JSONSerialization.data(withJSONObject:)` for building request payloads. This is intentional -- keeps the format flexible for the `attachments` array inside `messages`.
- **Do NOT add mutable state to CloudLLMClient:** D-04 specifies all dependencies as `let`. No health state tracking (unlike LocalLLMClient which has `LocalLLMHealthState` actor). Cloud endpoint is always remote -- no local health probing needed.
- **Do NOT change the LLMClient protocol:** D-03 is explicit. CloudLLMClient conforms as-is.
- **Do NOT retry file upload:** D-05 specifies upload errors fail immediately. Only chat/completions retries.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OAuth token management | Token fetching/caching/refresh | SberAuthService.getAccessToken() | Already handles caching, refresh margin, in-flight coalescing [VERIFIED: SberAuthService.swift] |
| Certificate pinning | Custom TLS delegate | SberTrustPolicy.urlSession | Already configures URLSession with SberRootCA.pem [VERIFIED: SberTrustPolicy.swift] |
| HTTP transport abstraction | Custom networking layer | HTTPClient protocol + URLSession conformance | Already exists with MockHTTPClient for tests [VERIFIED: HTTPClient.swift] |
| LLM error types | New error enum | LLMError (existing) | All cases already present: networkError, invalidResponse, parsingFailed, rateLimited, serverError, timeout [VERIFIED: LLMClient.swift] |

**Key insight:** Phase 10-11 built the entire infrastructure. Phase 12 assembles existing pieces into a new client class. The only truly new code is: multipart body construction, file ID extraction from upload response, and chat/completions request with attachments field.

## Common Pitfalls

### Pitfall 1: Multipart Boundary in Content-Type Header
**What goes wrong:** Forgetting to include the boundary string in the Content-Type header, or using a different boundary in the header vs body.
**Why it happens:** Multipart requires `Content-Type: multipart/form-data; boundary=<boundary>` AND the same boundary in the body delimiters.
**How to avoid:** Generate boundary once (UUID), use in both header and body construction.
**Warning signs:** 400 Bad Request from /files endpoint.

### Pitfall 2: Missing CRLF in Multipart Body
**What goes wrong:** Using `\n` instead of `\r\n` in multipart body delimiters, or missing trailing CRLF after binary data.
**Why it happens:** HTTP spec requires CRLF (`\r\n`), not just LF (`\n`).
**How to avoid:** Always use `\r\n` literal strings. Final boundary must end with `\r\n`.
**Warning signs:** Server can't parse the file from the multipart body.

### Pitfall 3: Empty Content String for Audio Message
**What goes wrong:** Sending no `content` field in the user message when only attachments are present.
**Why it happens:** GigaChat SDK model has `content: str = Field(default="")` -- content is always present, even if empty string.
**How to avoid:** Always include `"content": ""` in the user message alongside `"attachments": [fileId]`.
**Warning signs:** 400 from chat/completions.

### Pitfall 4: Retry Delay Blocking Main Thread
**What goes wrong:** Using `Thread.sleep()` instead of `Task.sleep()` for retry delay.
**Why it happens:** Habit from synchronous code.
**How to avoid:** Use `try await Task.sleep(nanoseconds:)` which is cooperative and cancellable.
**Warning signs:** UI freeze during retry wait.

### Pitfall 5: Not Mapping AuthError Before Throwing
**What goes wrong:** AuthError leaks through CloudLLMClient boundary, callers don't handle it.
**Why it happens:** Forgetting the catch for AuthError when calling `getAccessToken()`.
**How to avoid:** Wrap every `getAccessToken()` call in do/catch that maps AuthError -> LLMError per D-07.
**Warning signs:** Callers receive unexpected error types.

### Pitfall 6: CancellationError Swallowed by Error Mapping
**What goes wrong:** A CancellationError gets caught by a generic catch and mapped to LLMError.
**Why it happens:** `do { try await ... } catch { throw mapToLLMError(error) }` catches everything.
**How to avoid:** Check for CancellationError FIRST, rethrow it before any mapping. Copy pattern from LocalLLMClient.
**Warning signs:** Task cancellation doesn't propagate properly.

## Code Examples

### Complete CloudLLMClient Structure
```swift
// Source: Synthesized from prototype GigaChatClient + LocalLLMClient + SDK analysis
import Foundation
import OSLog

final class CloudLLMClient: LLMClient, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "CloudLLMClient")

    private let authService: AuthService
    private let httpClient: HTTPClient
    private let configuration: CloudLLMConfiguration

    init(
        authService: AuthService,
        httpClient: HTTPClient,
        configuration: CloudLLMConfiguration = CloudLLMConfiguration()
    ) {
        self.authService = authService
        self.httpClient = httpClient
        self.configuration = configuration
    }

    // MARK: - LLMClient conformance (text path)
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        // Text-only path: same as prototype GigaChatClient.normalize
        // Builds system+user messages, calls sendChatCompletion
    }

    // MARK: - Cloud audio path
    func processAudio(audioData: Data, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        // 1. Get token
        // 2. Upload WAV -> file ID
        // 3. Call chat/completions with file ID attachment
        // 4. On retryable error at step 3 -> retry once with backoff
    }
}
```

### GigaChat API File Upload Request/Response
```swift
// Source: GigaChat Python SDK (ai-forever/gigachat, api/files.py + models/files.py)
// POST https://gigachat.devices.sberbank.ru/api/v1/files
// Headers:
//   Authorization: Bearer <token>
//   Content-Type: multipart/form-data; boundary=<boundary>
// Body: multipart with fields:
//   - purpose: "general" (Literal["general", "assistant"])
//   - file: (filename, data, content-type)
//
// Response 200:
// {
//   "id": "file-uuid-here",         // File identifier (string)
//   "object": "file",               // Object type
//   "bytes": 123456,                // File size in bytes (int)
//   "created_at": 1710000000,       // Unix timestamp (int)
//   "filename": "audio.wav",        // Original filename (string)
//   "purpose": "general"            // Purpose (string)
// }
```

### GigaChat API Chat Completions with Attachment
```swift
// Source: GigaChat Python SDK (ai-forever/gigachat, models/chat.py)
// POST https://gigachat.devices.sberbank.ru/api/v1/chat/completions
// Headers:
//   Authorization: Bearer <token>
//   Content-Type: application/json
//
// Body:
// {
//   "model": "GigaChat-2-Max",
//   "temperature": 0.1,
//   "messages": [
//     {
//       "role": "system",
//       "content": "<system prompt from SuperTextStyle.systemPrompt()>"
//     },
//     {
//       "role": "user",
//       "content": "",
//       "attachments": ["<file-id-from-upload>"]
//     }
//   ]
// }
//
// Response 200:
// {
//   "choices": [
//     {
//       "message": {
//         "role": "assistant",
//         "content": "Normalized text here"
//       },
//       "index": 0,
//       "finish_reason": "stop"
//     }
//   ],
//   "model": "GigaChat-2-Max",
//   "usage": { "prompt_tokens": N, "completion_tokens": N, "total_tokens": N },
//   "object": "chat.completion"
// }
```

### Data.append String Extension
```swift
// Source: Standard Swift pattern (swiftbysundell.com/articles/http-post-and-file-upload-requests-using-urlsession)
private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
```

### isRetryable Extension (port from prototype)
```swift
// Source: Prototype govorun/Services/GigaChatClient.swift lines 153-162
extension LLMError {
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout:
            true
        default:
            false
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GigaChat-2 (prototype) | GigaChat-2-Max (ROADMAP) | 2026 | New model supports audio-in multimodal input |
| Text-only GigaChatClient | CloudLLMClient with audio upload | Phase 12 | Two-step flow: upload + completions instead of single text call |
| Retry entire request | Retry only completions, reuse file ID | Phase 12 D-05 | Less bandwidth, faster retry |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GigaChat `attachments` field in user message accepts audio file IDs (not just images) | Architecture Patterns, Pattern 1 | HIGH -- if GigaChat-2-Max doesn't support audio via attachments, the entire approach fails. SDK shows `attachments: Optional[List[str]]` without type restriction. Sber search results confirm audio files up to 35MB supported for upload. |
| A2 | User message `content` can be empty string when attachments present | Common Pitfalls, Pitfall 3 | MEDIUM -- if API requires non-empty content, need to pass a placeholder. SDK default is `content=""`. |
| A3 | `purpose: "general"` is correct for audio file upload | Code Examples | LOW -- SDK shows `Literal["general", "assistant"]`, "general" is default. If wrong purpose, upload may fail with 400. |
| A4 | GigaChat-2-Max returns plain text in `choices[0].message.content` for audio-in (not structured object) | Architecture Patterns | MEDIUM -- if content is a complex object (like with image generation), parsing logic needs adjustment. Prototype confirms text extraction from same field. |

## Open Questions

1. **Audio file size limit for WAV uploads**
   - What we know: Sber documentation states 35 MB max for audio files [CITED: developers.sber.ru search results]
   - What's unclear: Whether there are format constraints beyond WAV (sample rate, bit depth, mono/stereo requirements for GigaChat-2-Max)
   - Recommendation: Start with whatever WAV format AudioCapture produces (16kHz mono PCM Int16). If rejected, error will be clear from API response.

2. **Exact retry delay value**
   - What we know: Prototype uses 0.5s fixed delay. SDK uses exponential backoff with factor 0.5 and formula `factor * 2^attempt + jitter`. Success criteria says "exponential backoff".
   - What's unclear: Whether to match SDK's exact formula or use simpler single-retry delay.
   - Recommendation: Use 0.5s for single retry (matching prototype). With only 1 retry, exponential backoff simplifies to a single fixed delay.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (system, ~986 tests in 40 files) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/CloudLLMClientTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLOUD-01 | WAV uploaded via /api/v1/files with multipart/form-data | unit | `xcodebuild test ... -only-testing:GovorunTests/CloudLLMClientTests/test_processAudio_uploadsWAVFile` | Wave 0 |
| CLOUD-02 | /chat/completions called with file ID attachment + system prompt | unit | `xcodebuild test ... -only-testing:GovorunTests/CloudLLMClientTests/test_processAudio_callsCompletionsWithAttachment` | Wave 0 |
| CLOUD-03 | Response text extracted from choices[0].message.content | unit | `xcodebuild test ... -only-testing:GovorunTests/CloudLLMClientTests/test_processAudio_extractsResponseText` | Wave 0 |
| CLOUD-06 | Timeout 30s, retry with backoff on 429/5xx | unit | `xcodebuild test ... -only-testing:GovorunTests/CloudLLMClientTests/test_processAudio_retriesOnServerError` | Wave 0 |

### Sampling Rate
- **Per task commit:** Quick run on CloudLLMClientTests only
- **Per wave merge:** Full suite (`xcodebuild test -scheme Govorun ...`)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `GovorunTests/CloudLLMClientTests.swift` -- covers CLOUD-01, CLOUD-02, CLOUD-03, CLOUD-06 + error mapping + LLMClient conformance
- [ ] `Govorun/Services/CloudLLMClient.swift` + `CloudLLMConfiguration` in same file or LLMClient.swift

*(Test infrastructure exists: MockHTTPClient, MockAuthService, XCTest, xctestplan all in place)*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | SberAuthService (actor-based OAuth, token caching + refresh margin) -- existing, no changes |
| V3 Session Management | no | N/A -- stateless API calls |
| V4 Access Control | no | N/A -- client-side only |
| V5 Input Validation | yes | Validate HTTP status codes, JSON response structure, non-empty content |
| V6 Cryptography | yes | SberTrustPolicy (certificate pinning with SberRootCA.pem) -- existing, no changes |

### Known Threat Patterns for GigaChat API Client

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Token leakage in logs | Information Disclosure | OSLog with privacy: .private for token values |
| MITM on Sber API | Tampering | SberTrustPolicy certificate pinning [VERIFIED: existing] |
| Credential exposure | Information Disclosure | Credentials in Keychain only (CredentialStore) [VERIFIED: existing] |
| Response injection | Tampering | Validate JSON structure before extracting content |
| Rate limit exhaustion | Denial of Service | Single retry with backoff, no infinite retry loops |

## Sources

### Primary (HIGH confidence)
- GigaChat Python SDK source code (`ai-forever/gigachat` repo, cloned locally) -- file upload API contract (`api/files.py`), chat model with attachments (`models/chat.py`), response models (`models/files.py`), settings (`settings.py`), retry logic (`retry.py`)
- Existing codebase files:
  - `Govorun/Services/LLMClient.swift` -- LLMClient protocol, LLMError, LocalLLMConfiguration
  - `Govorun/Services/LocalLLMClient.swift` -- reference implementation pattern
  - `Govorun/Services/HTTPClient.swift` -- HTTPClient protocol + MockHTTPClient
  - `Govorun/Services/SberAuthService.swift` -- AuthService protocol, AuthError, SberAuthService, MockAuthService
  - `Govorun/Services/SberTrustPolicy.swift` -- TrustPolicyProviding, certificate pinning URLSession
- Prototype `govorun/Services/GigaChatClient.swift` -- sendRequest, parseResponse, isRetryable

### Secondary (MEDIUM confidence)
- [Sber developers documentation search results](https://developers.sber.ru/docs/ru/gigachat/guides/working-with-files) -- confirmed audio file upload limit 35MB, `/api/v1/files` endpoint
- [Sber developer portal](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-file) -- POST /files reference page (client-side rendered, content not extractable via fetch)
- [Swift by Sundell - multipart upload](https://www.swiftbysundell.com/articles/http-post-and-file-upload-requests-using-urlsession/) -- URLSession multipart form-data patterns

### Tertiary (LOW confidence)
- GigaChat-2-Max audio-in capability assumption -- based on ROADMAP spec and Sber search results mentioning audio support, but exact audio-in behavior not verified against official docs (client-side rendered)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all system frameworks, no new dependencies, verified against existing codebase
- Architecture: HIGH -- exact API contract verified from SDK source code, existing patterns well-documented
- Pitfalls: HIGH -- multipart format, CRLF, CancellationError are well-known URLSession pitfalls
- API contract (attachments field for audio): MEDIUM -- SDK confirms field exists but audio-in behavior inferred from context

**Research date:** 2026-04-12
**Valid until:** 2026-05-12 (stable -- system frameworks and GigaChat API unlikely to change)
