import Foundation
import Security

// MARK: - Ошибки

enum CredentialStoreError: Error, Equatable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}

// MARK: - Протокол

protocol CredentialStoring: Sendable {
    func save(clientId: String, clientSecret: String) throws
    func get() -> (clientId: String, secret: String)?
    func delete() throws
}

// MARK: - Реализация

final class CredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let service: String

    private enum Keys {
        static let defaultService = "com.govorun.app.credentials"
        static let clientId = "gigachat.clientId"
        static let clientSecret = "gigachat.clientSecret"
    }

    init(serviceOverride: String? = nil) {
        self.service = serviceOverride ?? Keys.defaultService
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
              let secret = readItem(account: Keys.clientSecret)
        else {
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

    // MARK: - Private

    private func saveItem(account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        // Удаляем старое значение (upsert: delete-then-add)
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    private func readItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue as Any,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}

// MARK: - Мок

final class MockCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (clientId: String, secret: String)?
    private(set) var saveCalls: [(clientId: String, secret: String)] = []
    var saveError: Error?
    var deleteError: Error?

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
        if let error = deleteError { throw error }
        stored = nil
    }
}
