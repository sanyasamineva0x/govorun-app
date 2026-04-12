import XCTest
@testable import Govorun

final class CredentialStoreTests: XCTestCase {
    private var store: MockCredentialStore!

    override func setUp() {
        super.setUp()
        store = MockCredentialStore()
    }

    // MARK: - Save / Get

    func test_save_storesCredentials() throws {
        try store.save(clientId: "test-id", clientSecret: "test-secret")
        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "test-id")
        XCTAssertEqual(creds?.secret, "test-secret")
    }

    func test_get_whenEmpty_returnsNil() {
        XCTAssertNil(store.get())
    }

    func test_save_overwritesPrevious() throws {
        try store.save(clientId: "old-id", clientSecret: "old-secret")
        try store.save(clientId: "new-id", clientSecret: "new-secret")
        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "new-id")
        XCTAssertEqual(creds?.secret, "new-secret")
    }

    // MARK: - Delete

    func test_delete_clearsCredentials() throws {
        try store.save(clientId: "id", clientSecret: "secret")
        try store.delete()
        XCTAssertNil(store.get())
    }

    func test_delete_whenEmpty_doesNotThrow() throws {
        XCTAssertNoThrow(try store.delete())
    }

    // MARK: - Error injection

    func test_save_withError_throws() {
        store.saveError = CredentialStoreError.saveFailed(-25299)
        XCTAssertThrowsError(try store.save(clientId: "id", clientSecret: "secret")) { error in
            XCTAssertEqual(error as? CredentialStoreError, .saveFailed(-25299))
        }
    }

    func test_delete_withError_throws() {
        store.deleteError = CredentialStoreError.deleteFailed(-25300)
        XCTAssertThrowsError(try store.delete()) { error in
            XCTAssertEqual(error as? CredentialStoreError, .deleteFailed(-25300))
        }
    }

    // MARK: - Call tracking

    func test_save_tracksCalls() throws {
        try store.save(clientId: "a", clientSecret: "b")
        try store.save(clientId: "c", clientSecret: "d")
        XCTAssertEqual(store.saveCalls.count, 2)
        XCTAssertEqual(store.saveCalls[0].clientId, "a")
        XCTAssertEqual(store.saveCalls[1].clientId, "c")
    }

    // MARK: - Error Equatable

    func test_credentialStoreError_equatable() {
        XCTAssertEqual(CredentialStoreError.saveFailed(-25299), CredentialStoreError.saveFailed(-25299))
        XCTAssertNotEqual(CredentialStoreError.saveFailed(-25299), CredentialStoreError.saveFailed(-1))
        XCTAssertNotEqual(CredentialStoreError.saveFailed(-1), CredentialStoreError.deleteFailed(-1))
    }
}
