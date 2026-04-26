@testable import Govorun
import XCTest

final class ProductModeTests: XCTestCase {
    // MARK: - rawValue

    func test_cloud_rawValue() {
        XCTAssertEqual(ProductMode.cloud.rawValue, "cloud")
    }

    // MARK: - usesLLM

    func test_cloud_usesLLM() {
        XCTAssertTrue(ProductMode.cloud.usesLLM)
    }

    func test_super_usesLLM() {
        XCTAssertTrue(ProductMode.superMode.usesLLM)
    }

    func test_standard_usesLLM() {
        XCTAssertFalse(ProductMode.standard.usesLLM)
    }

    // MARK: - usesLocalLLM

    func test_cloud_usesLocalLLM() {
        XCTAssertFalse(ProductMode.cloud.usesLocalLLM)
    }

    func test_super_usesLocalLLM() {
        XCTAssertTrue(ProductMode.superMode.usesLocalLLM)
    }

    func test_standard_usesLocalLLM() {
        XCTAssertFalse(ProductMode.standard.usesLocalLLM)
    }

    // MARK: - isCloud

    func test_cloud_isCloud() {
        XCTAssertTrue(ProductMode.cloud.isCloud)
    }

    func test_super_isCloud() {
        XCTAssertFalse(ProductMode.superMode.isCloud)
    }

    func test_standard_isCloud() {
        XCTAssertFalse(ProductMode.standard.isCloud)
    }

    // MARK: - title / subtitle

    func test_cloud_title() {
        XCTAssertEqual(ProductMode.cloud.title, "Говорун Cloud")
    }

    func test_cloud_subtitle() {
        XCTAssertEqual(ProductMode.cloud.subtitle, "Диктовка, генерация и редактирование текста с Гигачатом")
    }

    // MARK: - Codable

    func test_codable_roundtrip_cloud() throws {
        let data = try JSONEncoder().encode(ProductMode.cloud)
        let decoded = try JSONDecoder().decode(ProductMode.self, from: data)
        XCTAssertEqual(decoded, .cloud)
    }

    // MARK: - CaseIterable

    func test_caseIterable_includes_cloud() {
        XCTAssertEqual(ProductMode.allCases.count, 3)
        XCTAssertTrue(ProductMode.allCases.contains(.cloud))
    }
}
