# Phase 10: TLS & Credentials - Research

**Researched:** 2026-04-12
**Domain:** Security.framework (Keychain + TLS trust), URLSession custom delegate, certificate bundling
**Confidence:** HIGH

## Summary

Phase 10 ports three components from the govorun prototype to govorun-app: (1) SberRootCA.pem certificate bundling with PEM parsing via Security.framework, (2) SberTrustPolicy + SberTrustDelegate for custom CA trust on `*.sberbank.ru` domains while preserving system CA trust, (3) CredentialStore rewrite from KeychainAccess SPM to raw Security.framework (SecItemAdd/SecItemCopyMatching/SecItemDelete), and (4) HTTPClient protocol with URLSession conformance for dependency injection.

The prototype code in `/Users/sanyasamineva/Desktop/govorun/` is production-quality for the TLS layer -- SberTrustPolicy already uses the correct modern APIs (SecTrustEvaluateWithError, SecTrustSetAnchorCertificatesOnly with false). The main work is: strip GRPC/NIOSSL dependencies, replace `static let shared` singleton with DI-based instance, rewrite CredentialStore from KeychainAccess to Security.framework, simplify CredentialStoring protocol from 7 methods to 3 (D-01/D-02), and add SberTrustPolicy failable init per D-05.

**Primary recommendation:** Port prototype SberTrustPolicy nearly verbatim (removing GRPC/NIO), rewrite CredentialStore using raw SecItem* APIs with `kSecClassGenericPassword`, and create tests through protocol mocks (MockCredentialStore, MockHTTPClient) rather than touching real Keychain.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** One credential pair only -- clientId + clientSecret for GigaChat. No STT/Legacy keys from prototype. Extend later if needed.
- **D-02:** Protocol CredentialStoring: three methods -- `save(clientId:clientSecret:)`, `get() -> (clientId, secret)?`, `delete()`. Full lifecycle for UI reset.
- **D-03:** Implementation via Security.framework (SecItemAdd/SecItemCopyMatching/SecItemDelete), no KeychainAccess SPM. Zero new dependencies.
- **D-04:** Graceful degradation on PEM load failure -- Cloud mode unavailable, Standard and Super work as usual. Error logged via OSLog.
- **D-05:** Certificate loaded in SberTrustPolicy init. Failable initializer (throws or returns nil) -- error detected immediately, not on first request.
- **D-06:** HTTPClient -- simple protocol with `data(for: URLRequest) async throws -> (Data, URLResponse)`. URLSession conforms directly (extension). Same as prototype.
- **D-07:** Trust and HTTP -- separate injectable concerns. SberTrustPolicy creates URLSession with SberTrustDelegate. This URLSession is passed as HTTPClient to SberAuthService and CloudLLMClient via AppState.
- **D-08:** SberTrustPolicy -- instance via DI (created in AppState, passed through init). No `static let shared` singleton. Consistent with project pattern.

### Claude's Discretion
- Keychain service name and keys (e.g., `com.govorun.app.credentials`)
- SberTrustDelegate -- concrete URLSessionDelegate implementation for cert validation
- File placement (CredentialStore -> Storage/, SberTrustPolicy -> Services/, HTTPClient -> Services/)
- Error enum naming and cases (TrustPolicyError, CredentialStoreError)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | SberRootCA.pem bundled in app for TLS with Sber API | PEM file exists in prototype at `/govorun/Resources/Certificates/SberRootCA.pem` (4634 bytes, 2 certificates -- Russian Trusted Root CA + Sub CA). Copy to `Govorun/Resources/Certificates/` and add to project.yml sources. PEM parsing code verified in prototype SberTrustPolicy.swift. |
| INFRA-02 | SberTrustPolicy implements URLSessionDelegate for certificate pinning on `*.sberbank.ru` | Prototype has complete working implementation: SberTrustDelegate with SecTrustSetAnchorCertificates + SecTrustSetAnchorCertificatesOnly(false) + SecTrustEvaluateWithError. Domain matching covers `.sberbank.ru`, `.sber.ru`. Strip GRPC/NIO, change to failable init, remove singleton. |
| INFRA-03 | CredentialStore stores clientId and clientSecret in Keychain (Security.framework) | Prototype uses KeychainAccess -- must rewrite to raw SecItemAdd/SecItemCopyMatching/SecItemDelete with kSecClassGenericPassword. Simplify from 7 methods (STT+LLM+Legacy) to 3 methods per D-02. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **No Co-Authored-By** in commits -- public repo, no AI authorship signs
- **Commits in Russian**: `feat: добавить X`, `fix: исправить Y`
- **TDD**: test (red) -> code (green) -> refactor
- **All services via protocols** + DI through init
- **Mocks in tests**, never real APIs/Keychain
- **Typed errors**: `enum XxxError: Error, Equatable { ... }` with `LocalizedError` for user-facing
- **async/await**, not completion handlers
- **@MainActor only for UI code**
- **No force unwrap (!)** in production code
- **Zero new SPM dependencies** for this phase
- **Strict concurrency**: `SWIFT_STRICT_CONCURRENCY: complete`
- **Layer rules**: Core/ no SwiftUI/AppKit, Services/ no AppKit, Models/ pure value types
- **OSLog**: `Logger(subsystem: "com.govorun.app", category: "ClassName")`
- **private enum Keys** for string constants

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Security.framework | system (macOS 14.0+) | Keychain (SecItem*) + TLS trust (SecTrust*, SecCertificate*) | Apple's native framework, zero dependencies, project mandate (D-03) [VERIFIED: project.yml macOS 14.0+ deployment target] |
| Foundation | system | URLSession, URLRequest, Data, Bundle | Standard networking layer [VERIFIED: existing codebase usage] |
| OSLog | system | Structured logging for PEM load failures (D-04) | Project standard per existing codebase pattern [VERIFIED: 6 files use Logger(subsystem:category:)] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XCTest | system | Unit testing for all components | Testing CredentialStore protocol conformance, SberTrustPolicy PEM parsing, HTTPClient mocking |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw Security.framework | KeychainAccess SPM | Simpler API but adds dependency -- rejected by D-03 |
| Raw Security.framework | Swift Crypto / CryptoKit | Not needed -- SecCertificateCreateWithData handles PEM->DER, CryptoKit already used for SHA256 elsewhere but not relevant here |

**Installation:**
```bash
# No installation -- all system frameworks
```

## Architecture Patterns

### Recommended Project Structure
```
Govorun/
  Resources/
    Certificates/
      SberRootCA.pem           # [NEW] Copy from prototype
  Services/
    SberTrustPolicy.swift      # [NEW] TrustPolicyProviding protocol + SberTrustPolicy + SberTrustDelegate
    HTTPClient.swift           # [NEW] HTTPClient protocol + URLSession extension
  Storage/
    CredentialStore.swift      # [NEW] CredentialStoring protocol + CredentialStore (Security.framework)
GovorunTests/
  SberTrustPolicyTests.swift   # [NEW] PEM parsing, domain matching, failable init
  CredentialStoreTests.swift   # [NEW] Protocol-based mock testing
  HTTPClientTests.swift        # [NEW] URLSession conformance, mock testing
```

### Pattern 1: Failable Init for SberTrustPolicy (D-05)
**What:** SberTrustPolicy throws on init if PEM cannot be loaded, rather than silently failing on first request.
**When to use:** Always -- D-05 mandates fail-early.
**Example:**
```swift
// Source: Prototype SberTrustPolicy.swift (lines 33-56, adapted)
import Foundation
import Security
import OSLog

enum TrustPolicyError: Error, Equatable {
    case pemNotFound
    case certificateParsingFailed
}

protocol TrustPolicyProviding: Sendable {
    var urlSession: URLSession { get }
}

final class SberTrustPolicy: TrustPolicyProviding, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "SberTrustPolicy")
    
    let urlSession: URLSession
    private let secCertificates: [SecCertificate]

    init(bundle: Bundle = .main) throws {
        guard let pemPath = bundle.path(forResource: "SberRootCA", ofType: "pem") else {
            Self.logger.error("SberRootCA.pem не найден в бандле")
            throw TrustPolicyError.pemNotFound
        }

        let certs = Self.loadSecCertificates(from: pemPath)
        guard !certs.isEmpty else {
            Self.logger.error("Не удалось распарсить сертификаты из PEM")
            throw TrustPolicyError.certificateParsingFailed
        }

        self.secCertificates = certs

        let delegate = SberTrustDelegate(certificates: certs)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    // ... PEM parsing + domain matching from prototype
}
```

### Pattern 2: CredentialStore with Security.framework (D-01, D-02, D-03)
**What:** Thin wrapper around SecItem* APIs for one credential pair.
**When to use:** Always -- replaces KeychainAccess-based prototype.
**Example:**
```swift
// Source: Adapted from prototype CredentialStore.swift + verified SecItem* API patterns
import Foundation
import Security

enum CredentialStoreError: Error, Equatable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}

protocol CredentialStoring: Sendable {
    func save(clientId: String, clientSecret: String) throws
    func get() -> (clientId: String, secret: String)?
    func delete() throws
}

final class CredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()

    private enum Keys {
        static let service = "com.govorun.app.credentials"
        static let clientId = "gigachat.clientId"
        static let clientSecret = "gigachat.clientSecret"
    }

    func save(clientId: String, clientSecret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveItem(account: Keys.clientId, value: clientId)
        try saveItem(account: Keys.clientSecret, value: clientSecret)
    }

    func get() -> (clientId: String, secret: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = readItem(account: Keys.clientId),
              let secret = readItem(account: Keys.clientSecret) else {
            return nil
        }
        return (id, secret)
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteItem(account: Keys.clientId)
        try deleteItem(account: Keys.clientSecret)
    }

    // MARK: - Private SecItem wrappers

    private func saveItem(account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        // Удаляем старое значение если есть
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    private func readItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue as Any,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}
```

### Pattern 3: HTTPClient Protocol (D-06)
**What:** Minimal protocol for HTTP abstraction, URLSession conforms directly.
**When to use:** All network calls to Sber API go through this protocol.
**Example:**
```swift
// Source: Prototype SberAuthService.swift lines 27-31
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
```

### Pattern 4: Protocol Mocks for Testing
**What:** Mock implementations of CredentialStoring and HTTPClient for unit tests.
**When to use:** All tests -- never touch real Keychain or network.
**Example:**
```swift
// Source: Project convention from TestHelpers.swift pattern
final class MockCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (clientId: String, secret: String)?
    private(set) var saveCalls: [(clientId: String, secret: String)] = []
    var saveError: Error?

    func save(clientId: String, clientSecret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        saveCalls.append((clientId, clientSecret))
        if let error = saveError { throw error }
        stored = (clientId, clientSecret)
    }

    func get() -> (clientId: String, secret: String)? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}
```

### Anti-Patterns to Avoid
- **Singleton SberTrustPolicy:** D-08 explicitly forbids `static let shared`. Use init injection through AppState.
- **Testing real Keychain:** SecItem* in test runner requires entitlements and may leak state between test runs. Always mock via CredentialStoring protocol. [VERIFIED: project uses protocol mocks throughout TestHelpers.swift]
- **Force unwrap on PEM data:** If Data(contentsOf:) or base64 decoding fails, return empty array and let the failable init catch it. Never `!`.
- **Blocking URLSession creation on failure:** If PEM fails, do not create URLSession at all -- let the caller (AppState) handle graceful degradation (D-04).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PEM -> DER parsing | Custom ASN.1 parser | Prototype's `parsePEMCertificates` (string splitting + base64) + `SecCertificateCreateWithData` | Prototype code handles multi-cert PEM correctly, base64 edge cases covered |
| Keychain CRUD | Generic Keychain wrapper | Direct SecItemAdd/CopyMatching/Delete per-operation | Only 3 operations needed (D-02), generic wrapper is over-engineering |
| Certificate trust evaluation | Manual certificate chain verification | SecTrustSetAnchorCertificates + SecTrustEvaluateWithError | Apple's trust evaluation handles chain building, revocation, expiry -- never replicate |
| Thread safety | Actors for CredentialStore | NSLock (project convention) | Project uses `@unchecked Sendable + NSLock` pattern everywhere [VERIFIED: 13 files use NSLock] |

**Key insight:** The prototype already solves the hard problems (PEM parsing, trust evaluation, domain matching). This phase is primarily a port + simplification, not new development.

## Common Pitfalls

### Pitfall 1: SecTrustSetAnchorCertificatesOnly(true) breaks system CAs
**What goes wrong:** Calling `SecTrustSetAnchorCertificates` without `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` makes the trust engine ONLY trust your custom CA, rejecting all system CAs. Regular HTTPS (e.g., GitHub, Apple services) would break.
**Why it happens:** SecTrustSetAnchorCertificates replaces the default anchor set. The `Only` flag must be `false` to merge custom + system.
**How to avoid:** Always pair: `SecTrustSetAnchorCertificates(trust, certs)` then `SecTrustSetAnchorCertificatesOnly(trust, false)`. [VERIFIED: prototype does this correctly at line 141-142]
**Warning signs:** Non-Sber HTTPS requests start failing in tests or production.

### Pitfall 2: Keychain errSecDuplicateItem on save
**What goes wrong:** `SecItemAdd` returns `-25299` (errSecDuplicateItem) when an item with the same service+account already exists.
**Why it happens:** Unlike KeychainAccess which handles upsert, raw SecItemAdd is insert-only.
**How to avoid:** Delete before add (delete-then-add pattern), or use SecItemUpdate for existing items. Delete-then-add is simpler and sufficient for credentials that change rarely.
**Warning signs:** Second call to `save()` throws.

### Pitfall 3: PEM file not in test bundle
**What goes wrong:** Tests that instantiate SberTrustPolicy fail because SberRootCA.pem is not in the test target's bundle.
**Why it happens:** XCTest bundle is separate from app bundle. Unless the PEM is added to the test target's resources in project.yml, `Bundle.main` in tests points to the test runner.
**How to avoid:** (1) SberTrustPolicy accepts `Bundle` as init parameter (prototype already does this). (2) Tests use `Bundle(for: type(of: self))` or a test-specific PEM string. (3) For most tests, use MockTrustPolicy instead.
**Warning signs:** SberTrustPolicy tests throw `.pemNotFound` unexpectedly.

### Pitfall 4: kSecUseDataProtectionKeychain on macOS
**What goes wrong:** On macOS (unlike iOS), Keychain behavior differs depending on whether data protection keychain is used. Without `kSecUseDataProtectionKeychain: true`, items go to the legacy login keychain which has different access control.
**Why it happens:** macOS has both legacy and data protection keychains. Apple recommends data protection keychain for new code.
**How to avoid:** Add `kSecUseDataProtectionKeychain as String: true` to all SecItem queries. This makes behavior consistent with iOS and uses the modern keychain. [ASSUMED]
**Warning signs:** Items saved by the app are visible in Keychain Access.app under "login" keychain rather than app-specific storage.

### Pitfall 5: URLSession delegate strong reference cycle
**What goes wrong:** URLSession retains its delegate strongly. If SberTrustPolicy holds URLSession which holds SberTrustDelegate, the delegate must not hold back references to SberTrustPolicy.
**Why it happens:** URLSession's documented behavior -- it retains the delegate until `invalidateAndCancel()` or `finishTasksAndInvalidate()` is called.
**How to avoid:** SberTrustDelegate is a standalone class that only holds `[SecCertificate]` -- no reference back to SberTrustPolicy. Prototype already does this correctly. [VERIFIED: prototype SberTrustDelegate line 116-120]
**Warning signs:** Memory leaks in Instruments when SberTrustPolicy goes out of scope.

## Code Examples

Verified patterns from prototype and Apple documentation:

### PEM Parsing (from prototype, verified working)
```swift
// Source: /Users/sanyasamineva/Desktop/govorun/govorun/Services/SberTrustPolicy.swift lines 94-112
static func parsePEMCertificates(_ pem: String) -> [SecCertificate] {
    var certificates: [SecCertificate] = []
    let blocks = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----")

    for block in blocks {
        guard let endRange = block.range(of: "-----END CERTIFICATE-----") else { continue }
        let base64 = block[block.startIndex..<endRange.lowerBound]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let derData = Data(base64Encoded: base64),
              let cert = SecCertificateCreateWithData(nil, derData as CFData) else { continue }
        certificates.append(cert)
    }

    return certificates
}
```

### Domain Matching (from prototype, verified working)
```swift
// Source: /Users/sanyasamineva/Desktop/govorun/govorun/Services/SberTrustPolicy.swift lines 86-92
static func isSberDomain(_ host: String) -> Bool {
    let lowered = host.lowercased()
    return lowered.hasSuffix(".sberbank.ru")
        || lowered.hasSuffix(".sber.ru")
        || lowered == "sberbank.ru"
        || lowered == "sber.ru"
}
```

### SberTrustDelegate (from prototype, verified working)
```swift
// Source: /Users/sanyasamineva/Desktop/govorun/govorun/Services/SberTrustPolicy.swift lines 116-151
// Key logic: non-Sber domains get performDefaultHandling (system CAs)
// Sber domains get custom anchor + system anchor evaluation
private final class SberTrustDelegate: NSObject, URLSessionDelegate {
    private let certificates: [SecCertificate]

    init(certificates: [SecCertificate]) {
        self.certificates = certificates
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard SberTrustPolicy.isSberDomain(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, certificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, false)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

### SecItem* Keychain Operations (verified API pattern)
```swift
// Source: Apple Security.framework documentation + advancedswift.com verified pattern
// Save: SecItemAdd with kSecClassGenericPassword
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.govorun.app.credentials",
    kSecAttrAccount as String: "gigachat.clientId",
    kSecValueData as String: Data("value".utf8),
]
SecItemDelete(query as CFDictionary) // Upsert: delete first
let status = SecItemAdd(query as CFDictionary, nil)
// status == errSecSuccess

// Read: SecItemCopyMatching
let readQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.govorun.app.credentials",
    kSecAttrAccount as String: "gigachat.clientId",
    kSecMatchLimit as String: kSecMatchLimitOne,
    kSecReturnData as String: kCFBooleanTrue as Any,
]
var result: AnyObject?
let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
// readStatus == errSecSuccess, result as? Data

// Delete: SecItemDelete
let deleteQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.govorun.app.credentials",
    kSecAttrAccount as String: "gigachat.clientId",
]
let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
// deleteStatus == errSecSuccess || errSecItemNotFound
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SecTrustEvaluate (deprecated) | SecTrustEvaluateWithError | macOS 10.14+ | Returns CFError with details, boolean result. Prototype already uses correct API. [VERIFIED: prototype line 145] |
| NSURLConnection delegate | URLSessionDelegate | Years ago | Prototype already uses URLSession. [VERIFIED: prototype line 116] |
| Keychain kSecAttrAccessible | kSecUseDataProtectionKeychain | macOS 10.15+ | Recommended for new code to use data protection keychain on macOS. [CITED: Apple Developer Forums] |

**Deprecated/outdated:**
- `SecTrustEvaluate`: Deprecated, replaced by `SecTrustEvaluateWithError`. Prototype already uses the correct modern API.
- `SecTrustGetTrustResult`: Deprecated along with `SecTrustEvaluate`. Not needed with `SecTrustEvaluateWithError`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Adding `kSecUseDataProtectionKeychain: true` is recommended for macOS Keychain queries | Common Pitfalls (#4) | LOW -- without it, items still work but go to legacy keychain. Omitting it is safe, adding it is a best practice. Can validate at implementation time. |
| A2 | SberRootCA.pem from prototype is still valid and contains the correct Russian Trusted Root CA + Sub CA chain | Architecture Patterns | HIGH if wrong -- TLS would fail. Mitigated by: PEM file has 2032 expiry on Root CA, 2027 on Sub CA (visible in file). Validated by successful use in prototype. |

**If this table is empty:** N/A -- two assumptions identified above.

## Open Questions

1. **kSecUseDataProtectionKeychain on macOS 14+**
   - What we know: Apple recommends data protection keychain for new code on macOS 10.15+
   - What's unclear: Whether ad-hoc signed apps (no Developer ID) can use data protection keychain without issues. The test runner may also have different behavior.
   - Recommendation: Start without `kSecUseDataProtectionKeychain` flag (legacy keychain works fine for ad-hoc signed apps). Add later if needed. The protocol abstraction means the implementation detail is hidden.

2. **project.yml resource registration for SberRootCA.pem**
   - What we know: Files under `Govorun/` are auto-included via `sources: - path: Govorun`. PEM files in `Govorun/Resources/Certificates/` should be bundled automatically.
   - What's unclear: Whether XcodeGen treats `.pem` as a resource or requires explicit Copy Files phase.
   - Recommendation: Place in `Govorun/Resources/Certificates/`, verify with `Bundle.main.path(forResource:ofType:)` after xcodegen. If not found, add explicit Copy Files to project.yml.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (system, ~986 existing tests) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing GovorunTests/SberTrustPolicyTests -only-testing GovorunTests/CredentialStoreTests -only-testing GovorunTests/HTTPClientTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | PEM loads from bundle, parses into SecCertificate array | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing GovorunTests/SberTrustPolicyTests` | Wave 0 |
| INFRA-01 | Graceful failure when PEM missing (D-04) | unit | same | Wave 0 |
| INFRA-02 | SberTrustDelegate returns `.performDefaultHandling` for non-Sber domains | unit | same | Wave 0 |
| INFRA-02 | Domain matching: `.sberbank.ru`, `.sber.ru`, exact matches | unit | same | Wave 0 |
| INFRA-02 | Failable init throws on bad PEM (D-05) | unit | same | Wave 0 |
| INFRA-03 | CredentialStore save/get/delete lifecycle via mock | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing GovorunTests/CredentialStoreTests` | Wave 0 |
| INFRA-03 | CredentialStore returns nil when empty | unit | same | Wave 0 |
| INFRA-03 | CredentialStore handles save errors | unit | same | Wave 0 |
| D-06 | URLSession conforms to HTTPClient | unit | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing GovorunTests/HTTPClientTests` | Wave 0 |

### Sampling Rate
- **Per task commit:** quick run command (target-specific tests)
- **Per wave merge:** full suite command
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `GovorunTests/SberTrustPolicyTests.swift` -- covers INFRA-01, INFRA-02: PEM parsing, domain matching, failable init, error cases
- [ ] `GovorunTests/CredentialStoreTests.swift` -- covers INFRA-03: save/get/delete lifecycle through MockCredentialStore, error handling
- [ ] `GovorunTests/HTTPClientTests.swift` -- covers D-06: URLSession extension conformance verification

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A for this phase (OAuth is Phase 11) |
| V3 Session Management | no | N/A for this phase |
| V4 Access Control | no | N/A for this phase |
| V5 Input Validation | yes | Validate PEM format before parsing; validate Keychain OSStatus returns [VERIFIED: prototype validates base64 + SecCertificateCreateWithData return] |
| V6 Cryptography | yes | Use Security.framework (never hand-roll TLS or certificate verification); SecTrustEvaluateWithError for trust evaluation [VERIFIED: prototype uses correct APIs] |

### Known Threat Patterns for Security.framework + URLSession

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Man-in-the-middle on Sber API | Spoofing | Custom CA pinning via SberTrustDelegate + SecTrustEvaluateWithError |
| Credential extraction from Keychain | Information Disclosure | kSecClassGenericPassword with service scoping; macOS Keychain encryption at rest |
| Bypassing certificate validation | Tampering | Never `.useCredential` without SecTrustEvaluateWithError succeeding; `.cancelAuthenticationChallenge` on failure |
| PEM replacement in bundle | Tampering | Hardened Runtime enabled; ad-hoc code signing prevents modification post-build [VERIFIED: project.yml ENABLE_HARDENED_RUNTIME: true] |

## Sources

### Primary (HIGH confidence)
- Prototype source code: `/Users/sanyasamineva/Desktop/govorun/govorun/Services/SberTrustPolicy.swift` -- complete working TLS implementation
- Prototype source code: `/Users/sanyasamineva/Desktop/govorun/govorun/Services/SberAuthService.swift` -- HTTPClient protocol, CredentialStoring protocol
- Prototype source code: `/Users/sanyasamineva/Desktop/govorun/govorun/Storage/CredentialStore.swift` -- KeychainAccess-based implementation (reference for rewrite)
- Prototype certificate: `/Users/sanyasamineva/Desktop/govorun/govorun/Resources/Certificates/SberRootCA.pem` -- Russian Trusted Root CA + Sub CA
- govorun-app codebase: existing patterns (NSLock, protocols, Logger, TestHelpers) -- verified through Grep

### Secondary (MEDIUM confidence)
- [Advanced Swift - Keychain Tutorial](https://www.advancedswift.com/secure-private-data-keychain-swift/) -- SecItemAdd/CopyMatching/Delete API patterns verified
- [Linus Karlsson - Custom CA Validation](https://linuskarlsson.se/blog/validating-server-certificates-signed-by-own-ca-in-swift/) -- SecTrustSetAnchorCertificates + SecTrustSetAnchorCertificatesOnly pattern confirmed
- [Apple Developer Forums - kSecUseDataProtectionKeychain](https://developer.apple.com/forums/thread/131522) -- macOS Keychain differences

### Tertiary (LOW confidence)
- kSecUseDataProtectionKeychain recommendation for ad-hoc signed macOS apps -- needs validation at implementation time

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all system frameworks, zero dependencies, verified in prototype
- Architecture: HIGH -- prototype provides working reference code, project conventions well-documented
- Pitfalls: HIGH -- well-known Security.framework edge cases, verified against prototype which handles them correctly

**Research date:** 2026-04-12
**Valid until:** 2026-05-12 (stable -- system frameworks, no version churn)
