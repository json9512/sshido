import XCTest
@testable import sshidoCore
import sshidoModels

private struct FakeIdentities: IdentityRepository {
    let pems: [UUID: String]
    func all() async -> [Identity] { [] }
    func add(label: String, privateKeyPEM: String) async throws -> Identity { throw CredentialError.noKeyAttached }
    func loadPEM(for identityID: UUID) async throws -> String {
        guard let pem = pems[identityID] else { throw CredentialError.noKeyAttached }
        return pem
    }
    func remove(id: UUID) async throws {}
}

private struct FakeVault: PasswordVault {
    let passwords: [UUID: String]
    func storePassword(_ password: String, hostID: UUID) throws {}
    func loadPassword(hostID: UUID) throws -> String {
        guard let password = passwords[hostID] else { throw CredentialError.noKeyAttached }
        return password
    }
    func deletePassword(hostID: UUID) {}
}

final class ServicesTests: XCTestCase {
    private func host(_ method: HostAuthMethod, identity: UUID? = nil) -> RemoteHost {
        RemoteHost(id: UUID(), name: "box", hostname: "box.local", port: 22, username: "me",
                   identityID: identity, authMethod: method)
    }

    func testCredentialsResolveKeyAndPassword() async throws {
        let keyID = UUID()
        let passwordHost = host(.password)
        let credentials = HostCredentials(identities: FakeIdentities(pems: [keyID: "PEM"]),
                                          passwords: FakeVault(passwords: [passwordHost.id: "secret"]))
        let keyAuth = try await credentials.auth(for: host(.key, identity: keyID))
        XCTAssertEqual(keyAuth, .privateKeyPEM("PEM", passphrase: nil))
        let passwordAuth = try await credentials.auth(for: passwordHost)
        XCTAssertEqual(passwordAuth, .password("secret"))
    }

    func testKeyHostWithoutKeyFails() async {
        let credentials = HostCredentials(identities: FakeIdentities(pems: [:]), passwords: FakeVault(passwords: [:]))
        do {
            _ = try await credentials.auth(for: host(.key))
            XCTFail("a key host without a key must fail")
        } catch {
            XCTAssertEqual(error as? CredentialError, .noKeyAttached)
        }
    }
}
