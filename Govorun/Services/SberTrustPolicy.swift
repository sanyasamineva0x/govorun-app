import Foundation
import OSLog
import Security

// MARK: - Протокол

protocol TrustPolicyProviding: Sendable {
    var urlSession: URLSession { get }
}

// MARK: - Ошибки

enum TrustPolicyError: Error, Equatable {
    case pemNotFound
    case certificateParsingFailed
}

// MARK: - Реализация

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

        secCertificates = certs

        let delegate = SberTrustDelegate(certificates: certs)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - PEM -> SecCertificate

    static func loadSecCertificates(from path: String) -> [SecCertificate] {
        guard let pemData = FileManager.default.contents(atPath: path),
              let pemString = String(data: pemData, encoding: .utf8)
        else {
            return []
        }
        return parsePEMCertificates(pemString)
    }

    static func isSberDomain(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered.hasSuffix(".sberbank.ru")
            || lowered.hasSuffix(".sber.ru")
            || lowered == "sberbank.ru"
            || lowered == "sber.ru"
    }

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
                  let cert = SecCertificateCreateWithData(nil, derData as CFData)
            else { continue }
            certificates.append(cert)
        }

        return certificates
    }
}

// MARK: - URLSessionDelegate

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
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard SberTrustPolicy.isSberDomain(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, certificates as CFArray)
        // true = доверяем ТОЛЬКО вшитым CA Сбера (strict pinning).
        // guard isSberDomain выше отсекает не-сбер хосты, поэтому system CAs
        // для остальных доменов не задеваются (они идут performDefaultHandling).
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Мок для тестов

final class MockTrustPolicy: TrustPolicyProviding, @unchecked Sendable {
    let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
}
