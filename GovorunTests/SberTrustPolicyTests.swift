@testable import Govorun
import XCTest

final class SberTrustPolicyTests: XCTestCase {
    // MARK: - PEM Parsing

    func test_parsePEMCertificates_validPEM_returnsCertificates() {
        let pemPath = Bundle(for: type(of: self)).path(forResource: "SberRootCA", ofType: "pem")
            ?? Bundle.main.path(forResource: "SberRootCA", ofType: "pem")

        guard let path = pemPath,
              let data = FileManager.default.contents(atPath: path),
              let pemString = String(data: data, encoding: .utf8)
        else {
            XCTFail("SberRootCA.pem не найден в бандле")
            return
        }

        let certs = SberTrustPolicy.parsePEMCertificates(pemString)
        XCTAssertEqual(certs.count, 2)
    }

    func test_parsePEMCertificates_emptyString_returnsEmpty() {
        let certs = SberTrustPolicy.parsePEMCertificates("")
        XCTAssertTrue(certs.isEmpty)
    }

    func test_parsePEMCertificates_invalidBase64_returnsEmpty() {
        let invalidPEM = """
        -----BEGIN CERTIFICATE-----
        NOT_VALID_BASE64!!!
        -----END CERTIFICATE-----
        """
        let certs = SberTrustPolicy.parsePEMCertificates(invalidPEM)
        XCTAssertTrue(certs.isEmpty)
    }

    func test_parsePEMCertificates_partiallyInvalidPEM_parsesValidOnly() {
        let pemPath = Bundle(for: type(of: self)).path(forResource: "SberRootCA", ofType: "pem")
            ?? Bundle.main.path(forResource: "SberRootCA", ofType: "pem")

        guard let path = pemPath,
              let data = FileManager.default.contents(atPath: path),
              let pemString = String(data: data, encoding: .utf8)
        else {
            XCTFail("SberRootCA.pem не найден")
            return
        }

        let mixedPEM = pemString + "\n-----BEGIN CERTIFICATE-----\nINVALID\n-----END CERTIFICATE-----\n"
        let certs = SberTrustPolicy.parsePEMCertificates(mixedPEM)
        XCTAssertEqual(certs.count, 2)
    }

    // MARK: - Domain Matching

    func test_isSberDomain_sberbank_ru_returnsTrue() {
        XCTAssertTrue(SberTrustPolicy.isSberDomain("sberbank.ru"))
    }

    func test_isSberDomain_sber_ru_returnsTrue() {
        XCTAssertTrue(SberTrustPolicy.isSberDomain("sber.ru"))
    }

    func test_isSberDomain_subdomain_sberbank_returnsTrue() {
        XCTAssertTrue(SberTrustPolicy.isSberDomain("ngw.devices.sberbank.ru"))
    }

    func test_isSberDomain_subdomain_sber_returnsTrue() {
        XCTAssertTrue(SberTrustPolicy.isSberDomain("api.sber.ru"))
    }

    func test_isSberDomain_google_com_returnsFalse() {
        XCTAssertFalse(SberTrustPolicy.isSberDomain("google.com"))
    }

    func test_isSberDomain_notSberbank_returnsFalse() {
        XCTAssertFalse(SberTrustPolicy.isSberDomain("notsberbank.ru"))
    }

    func test_isSberDomain_caseInsensitive() {
        XCTAssertTrue(SberTrustPolicy.isSberDomain("SBERBANK.RU"))
        XCTAssertTrue(SberTrustPolicy.isSberDomain("Api.Sber.Ru"))
    }

    // MARK: - Init

    func test_init_validBundle_succeeds() throws {
        let policy = try SberTrustPolicy(bundle: .main)
        XCTAssertNotNil(policy.urlSession)
    }

    func test_init_emptyBundle_throwsPemNotFound() {
        let testBundle = Bundle(for: type(of: self))
        XCTAssertThrowsError(try SberTrustPolicy(bundle: testBundle)) { error in
            XCTAssertEqual(error as? TrustPolicyError, .pemNotFound)
        }
    }

    func test_init_invalidPEM_throwsCertificateParsingFailed() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let pemFile = tmpDir.appendingPathComponent("SberRootCA.pem")
        try "NOT A CERTIFICATE".write(to: pemFile, atomically: true, encoding: .utf8)

        let bundle = try XCTUnwrap(Bundle(path: tmpDir.path))
        XCTAssertThrowsError(try SberTrustPolicy(bundle: bundle)) { error in
            XCTAssertEqual(error as? TrustPolicyError, .certificateParsingFailed)
        }
    }

    // MARK: - MockTrustPolicy

    func test_mockTrustPolicy_conformsToProtocol() {
        let mock = MockTrustPolicy()
        let _: TrustPolicyProviding = mock
        XCTAssertNotNil(mock.urlSession)
    }
}
