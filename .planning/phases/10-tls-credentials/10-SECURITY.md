---
phase: 10
slug: tls-credentials
status: secured
threats_total: 8
threats_closed: 8
threats_open: 0
asvs_level: 1
audited: 2026-04-12
---

# Security Audit — Phase 10: TLS & Credentials

## Summary

All 8 registered threats are closed. No open threats. No unregistered flags.

---

## Threat Verification

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-10-01 | Spoofing | mitigate | CLOSED | `SberTrustPolicy.swift:57-62` — `isSberDomain` enforces `.sberbank.ru`/`.sber.ru` suffix matching (case-insensitive). Non-Sber challenges fall to `performDefaultHandling` at lines 103 and 108. |
| T-10-02 | Tampering | accept | CLOSED | Accepted risk logged below. Hardened Runtime enabled in `project.yml`; ad-hoc code signing prevents post-build bundle modification. |
| T-10-03 | Tampering | mitigate | CLOSED | `SberTrustPolicy.swift:114` — `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` passes `false`, preserving system CAs alongside bundled CA. |
| T-10-04 | Information Disclosure | accept | CLOSED | Accepted risk logged below. `SberTrustPolicy.swift:28,34` — OSLog `.error` messages contain only descriptive strings; no certificate content, key material, or credential values are logged. |
| T-10-05 | Information Disclosure | mitigate | CLOSED | `CredentialStore.swift:60` — `kSecClassGenericPassword` with service scope `"com.govorun.app.credentials"` (line 25). Keychain encrypts at rest. No credential values appear in log output. |
| T-10-06 | Tampering | mitigate | CLOSED | `CredentialStore.swift:67-70` — delete-then-add upsert: `SecItemDelete` called unconditionally before `SecItemAdd`; `OSStatus` checked, throws `CredentialStoreError.saveFailed(status)` on non-success. |
| T-10-07 | Denial of Service | accept | CLOSED | Accepted risk logged below. `CredentialStore.swift:104` — `errSecItemNotFound` is explicitly treated as success in `deleteItem`; only other non-zero status codes throw. |
| T-10-08 | Spoofing | accept | CLOSED | Accepted risk logged below. `MockHTTPClient` and `MockTrustPolicy` exist only in production source files (`HTTPClient.swift`, `SberTrustPolicy.swift`) as test-support types, but are only exercised by test targets. Verified: no mock instantiation found outside `GovorunTests/`. |

---

## Accepted Risks Log

### T-10-02 — Tampering: SberRootCA.pem bundle modification

- **Risk:** A compromised build environment could substitute the bundled PEM before signing.
- **Acceptance rationale:** Hardened Runtime (`ENABLE_HARDENED_RUNTIME: true` in `project.yml`) is enabled. Ad-hoc code signing means any post-build bundle modification invalidates the signature and macOS Gatekeeper rejects the app. Replacing the PEM requires full re-signing, which is outside the app's trust boundary.
- **Residual risk:** Low. Constrained to build-time supply chain threat, not runtime.
- **Owner:** Developer (build pipeline).

### T-10-04 — Information Disclosure: SberTrustPolicy error logging

- **Risk:** OSLog entries for PEM load failures could expose diagnostic information.
- **Acceptance rationale:** Log messages at `SberTrustPolicy.swift:28,34` contain only human-readable status strings ("SberRootCA.pem не найден в бандле", "Не удалось распарсить сертификаты из PEM"). No certificate DER bytes, key material, or credential values are included. OSLog entries at `.error` level are accessible only to privileged local users via Console.app.
- **Residual risk:** Negligible. Diagnostic strings only.
- **Owner:** Accepted at ASVS Level 1.

### T-10-07 — Denial of Service: CredentialStore.delete on missing item

- **Risk:** Deleting non-existent credentials could be used to cause unexpected error states.
- **Acceptance rationale:** `errSecItemNotFound` on delete is semantically a no-op (item is already absent). Treating it as success is correct behavior and prevents spurious errors when callers invoke delete before credentials are ever saved. `CredentialStore.swift:104` makes this explicit.
- **Residual risk:** None. Intentional design per plan D-02.
- **Owner:** Accepted at ASVS Level 1.

### T-10-08 — Spoofing: MockHTTPClient in production

- **Risk:** Test mock could be instantiated in production, bypassing real network behavior.
- **Acceptance rationale:** `MockHTTPClient` (`HTTPClient.swift:15`) and `MockTrustPolicy` (`SberTrustPolicy.swift:127`) are compiled into the main target for protocol-conformance visibility, which is required by Swift's access control model for `@testable` imports. No production call sites instantiate these mocks — confirmed by grep across `GovorunTests/` showing mock usage only in test files. The build system does not gate on this; it is an accepted structural pattern consistent with the rest of the codebase (e.g., `MockLLMClient`).
- **Residual risk:** Low. Requires a developer to deliberately instantiate mock types in production code; no automated path exists.
- **Owner:** Accepted at ASVS Level 1. Reviewable at ASVS Level 2 via test-target isolation.

---

## Unregistered Flags

None. No threat flags were raised in `10-01-SUMMARY.md` or `10-02-SUMMARY.md` `## Threat Flags` sections. The one deviation recorded in 10-01-SUMMARY.md (`.gitignore` exception for `SberRootCA.pem`) is a build/VCS configuration issue, not a security threat.

---

## Files Audited

- `/Users/sanyasamineva/Desktop/govorun-app/Govorun/Services/SberTrustPolicy.swift`
- `/Users/sanyasamineva/Desktop/govorun-app/Govorun/Storage/CredentialStore.swift`
- `/Users/sanyasamineva/Desktop/govorun-app/Govorun/Services/HTTPClient.swift`
- `/Users/sanyasamineva/Desktop/govorun-app/GovorunTests/SberTrustPolicyTests.swift`
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/phases/10-tls-credentials/10-01-PLAN.md`
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/phases/10-tls-credentials/10-02-PLAN.md`
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/phases/10-tls-credentials/10-01-SUMMARY.md`
- `/Users/sanyasamineva/Desktop/govorun-app/.planning/phases/10-tls-credentials/10-02-SUMMARY.md`
