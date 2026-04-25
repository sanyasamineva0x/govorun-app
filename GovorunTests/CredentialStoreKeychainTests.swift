@testable import Govorun
import XCTest

// MARK: - Keychain integration tests для реального CredentialStore

/// Тесты бьют реальный Keychain через unique service-identifier per test —
/// production-namespace `com.govorun.app.credentials` не затрагивается.
final class CredentialStoreKeychainTests: XCTestCase {
    private var store: CredentialStore!
    private var testServiceName: String!

    override func setUp() {
        super.setUp()
        testServiceName = "com.govorun.tests.\(UUID().uuidString)"
        store = CredentialStore(serviceOverride: testServiceName)
    }

    override func tearDown() {
        // Подчищаем за тестом — даже если он упал между save и assert.
        try? store.delete()
        store = nil
        testServiceName = nil
        super.tearDown()
    }

    // MARK: - Round-trip save/get/delete

    func test_save_thenGet_roundtrip() throws {
        try store.save(clientId: "real-id", clientSecret: "real-secret")

        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "real-id")
        XCTAssertEqual(creds?.secret, "real-secret")
    }

    func test_delete_afterSave_removesBoth() throws {
        try store.save(clientId: "id-A", clientSecret: "secret-A")
        XCTAssertNotNil(store.get())

        try store.delete()

        XCTAssertNil(store.get(), "после delete() оба item должны исчезнуть")
    }

    // MARK: - Idempotency + upsert

    func test_delete_idempotent_whenEmpty() {
        // errSecItemNotFound должен трактоваться как success — повторный delete не кидает.
        XCTAssertNoThrow(try store.delete())
        XCTAssertNoThrow(try store.delete())
    }

    func test_save_upserts_existing() throws {
        try store.save(clientId: "old-id", clientSecret: "old-secret")
        try store.save(clientId: "new-id", clientSecret: "new-secret")

        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "new-id")
        XCTAssertEqual(creds?.secret, "new-secret")
    }

    // MARK: - Edge cases (empty, unicode)

    func test_get_whenEmpty_returnsNil() {
        XCTAssertNil(store.get(), "пустой store не должен возвращать данные")
    }

    func test_save_emptyStrings_succeeds() throws {
        // Keychain не запрещает пустые value — поведение должно быть детерминированным.
        try store.save(clientId: "", clientSecret: "")

        let creds = store.get()
        XCTAssertEqual(creds?.clientId, "")
        XCTAssertEqual(creds?.secret, "")
    }

    func test_save_unicode_preservesExactValue() throws {
        let unicodeId = "клиент-🦊-id"
        let unicodeSecret = "секрет-✨-Test"
        try store.save(clientId: unicodeId, clientSecret: unicodeSecret)

        let creds = store.get()
        XCTAssertEqual(creds?.clientId, unicodeId)
        XCTAssertEqual(creds?.secret, unicodeSecret)
    }

    // MARK: - Concurrency + isolation

    func test_concurrent_saves_areSerialized() throws {
        // 10 параллельных save через NSLock не должны падать; финальный get() возвращает один из вариантов.
        let count = 10
        DispatchQueue.concurrentPerform(iterations: count) { i in
            try? self.store.save(clientId: "id-\(i)", clientSecret: "secret-\(i)")
        }

        let creds = store.get()
        XCTAssertNotNil(creds, "после concurrent saves должно остаться валидное значение")
        let id = creds?.clientId ?? ""
        XCTAssertTrue(id.hasPrefix("id-"), "финальное значение должно быть из записанных вариантов")
    }

    func test_two_instances_with_different_service_areIsolated() throws {
        let serviceB = "com.govorun.tests.\(UUID().uuidString)"
        let storeB = CredentialStore(serviceOverride: serviceB)
        defer { try? storeB.delete() }

        try store.save(clientId: "from-A", clientSecret: "secret-A")
        try storeB.save(clientId: "from-B", clientSecret: "secret-B")

        XCTAssertEqual(store.get()?.clientId, "from-A", "service A не должен видеть запись из B")
        XCTAssertEqual(storeB.get()?.clientId, "from-B", "service B не должен видеть запись из A")
    }
}
