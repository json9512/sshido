import Foundation
import Security

public enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
    case notFound
    case decoding
}

public struct KeychainKeyStore: Sendable {
    public init() {}

    public func store(privateKeyPEM: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "sshido.ssh-key",
            kSecValueData as String: privateKeyPEM,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func load(tag: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "sshido.ssh-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data else { throw KeychainError.decoding }
        return data
    }

    public func storePassword(_ password: String, hostID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostID.uuidString,
            kSecAttrService as String: "sshido.password",
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func loadPassword(hostID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostID.uuidString,
            kSecAttrService as String: "sshido.password",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
            throw KeychainError.decoding
        }
        return s
    }

    public func deletePassword(hostID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hostID.uuidString,
            kSecAttrService as String: "sshido.password",
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func delete(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "sshido.ssh-key",
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
