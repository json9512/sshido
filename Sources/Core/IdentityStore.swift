import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor IdentityStore {
    public static let shared = IdentityStore()

    private let url: URL
    private let keys = KeychainKeyStore()
    private var cached: [Identity] = []

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("identities.json")
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([Identity].self, from: data) {
            self.cached = arr
        }
    }

    public func all() -> [Identity] { cached }

    public func identity(id: UUID) -> Identity? { cached.first { $0.id == id } }

    public func add(label: String, privateKeyPEM: String) throws -> Identity {
        let tag = "identity-\(UUID().uuidString)"
        try keys.store(privateKeyPEM: Data(privateKeyPEM.utf8), tag: tag)
        let identity = Identity(label: label, keychainTag: tag)
        cached.append(identity)
        try persist()
        return identity
    }

    public func loadPEM(for identityID: UUID) throws -> String {
        guard let identity = cached.first(where: { $0.id == identityID }) else {
            throw SSHError.invalidKey("identity not found")
        }
        let data = try keys.load(tag: identity.keychainTag)
        guard let pem = String(data: data, encoding: .utf8) else {
            throw SSHError.invalidKey("stored key is not UTF-8")
        }
        return pem
    }

    public func remove(id: UUID) throws {
        guard let identity = cached.first(where: { $0.id == id }) else { return }
        try? keys.delete(tag: identity.keychainTag)
        cached.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(cached)
        try data.write(to: url, options: .atomic)
    }
}
