import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public protocol HostRepository: Sendable {
    func all() async -> [RemoteHost]
    func upsert(_ host: RemoteHost) async throws
    func setRemoteHostname(_ name: String, for id: UUID) async throws
    func remove(id: UUID) async throws
}

public protocol IdentityRepository: Sendable {
    func all() async -> [Identity]
    func add(label: String, privateKeyPEM: String) async throws -> Identity
    func loadPEM(for identityID: UUID) async throws -> String
    func remove(id: UUID) async throws
}

public protocol KnownHostRepository: Sendable {
    func all() async -> [KnownHost]
    func remove(host: String, port: Int) async throws
}

public protocol PasswordVault: Sendable {
    func storePassword(_ password: String, hostID: UUID) throws
    func loadPassword(hostID: UUID) throws -> String
    func deletePassword(hostID: UUID)
}

public protocol PushServicing: Sendable {
    var deviceToken: String? { get async }
    var subscription: PushSubscription? { get async }
    var settings: PushSettings { get async }
    func setServerURL(_ url: String) async throws
    func resubscribe() async throws
    func setNotificationsEnabled(_ enabled: Bool) async throws
    func clearSubscription() async throws
}

public protocol AppearanceStoring: Sendable {
    var appearance: TerminalAppearance { get async }
    func set(_ new: TerminalAppearance) async throws
}

public protocol ShortcutGroupStoring: Sendable {
    var groups: [ShortcutGroup] { get async }
    func addGroup(_ g: ShortcutGroup) async throws
    func removeGroup(id: UUID) async throws
    func updateGroup(_ g: ShortcutGroup) async throws
    func moveGroup(from source: IndexSet, to destination: Int) async throws
    func addShortcut(toGroup groupId: UUID, _ sc: CustomShortcut) async throws
    func removeShortcut(fromGroup groupId: UUID, shortcutId: UUID) async throws
    func updateShortcut(inGroup groupId: UUID, _ sc: CustomShortcut) async throws
}

public protocol SessionManaging: Sendable {
    func allSessions() async -> [Session]
    func sessions(for hostID: UUID) async -> [Session]
    func session(_ id: UUID) async -> Session?
    func openSession(for host: RemoteHost, auth: SSHAuth, title: String?) async -> Session
    func adoptRemoteSession(for host: RemoteHost, auth: SSHAuth, remote: RemoteTmuxSession) async -> Session
    func syncRemoteSessions(for host: RemoteHost, auth: SSHAuth) async throws -> [RemoteTmuxSession]
    func remoteShortHostname(for host: RemoteHost, auth: SSHAuth) async throws -> String?
    func renameSession(_ session: Session, host: RemoteHost, auth: SSHAuth, to newName: String) async throws -> Session
    func killRemoteSession(_ session: Session, host: RemoteHost, auth: SSHAuth) async throws
    func connectedSessionIDs(for hostID: UUID) async -> Set<UUID>
    func connectedHostIDs() async -> Set<UUID>
    func close(sessionID: UUID) async
}

extension HostStore: HostRepository {}
extension IdentityStore: IdentityRepository {}
extension KnownHostStore: KnownHostRepository {}
extension KeychainKeyStore: PasswordVault {}
extension PushService: PushServicing {}
extension AppearanceStore: AppearanceStoring {}
extension ShortcutGroupStore: ShortcutGroupStoring {}
extension SessionStore: SessionManaging {}

public enum CredentialError: LocalizedError, Equatable {
    case noKeyAttached

    public var errorDescription: String? {
        switch self {
        case .noKeyAttached: return "This server uses a key, but none is attached."
        }
    }
}

public struct HostCredentials: Sendable {
    private let identities: any IdentityRepository
    private let passwords: any PasswordVault

    public init(identities: any IdentityRepository, passwords: any PasswordVault) {
        self.identities = identities
        self.passwords = passwords
    }

    public func auth(for host: RemoteHost) async throws -> SSHAuth {
        switch host.authMethod {
        case .password:
            return .password(try passwords.loadPassword(hostID: host.id))
        case .key:
            guard let identityID = host.identityID else { throw CredentialError.noKeyAttached }
            return .privateKeyPEM(try await identities.loadPEM(for: identityID), passphrase: nil)
        }
    }
}

public struct AppServices: Sendable {
    public let hosts: any HostRepository
    public let identities: any IdentityRepository
    public let knownHosts: any KnownHostRepository
    public let passwords: any PasswordVault
    public let push: any PushServicing
    public let appearance: any AppearanceStoring
    public let shortcuts: any ShortcutGroupStoring
    public let sessions: any SessionManaging

    public init(hosts: any HostRepository, identities: any IdentityRepository, knownHosts: any KnownHostRepository,
                passwords: any PasswordVault, push: any PushServicing, appearance: any AppearanceStoring,
                shortcuts: any ShortcutGroupStoring, sessions: any SessionManaging) {
        self.hosts = hosts
        self.identities = identities
        self.knownHosts = knownHosts
        self.passwords = passwords
        self.push = push
        self.appearance = appearance
        self.shortcuts = shortcuts
        self.sessions = sessions
    }

    public var credentials: HostCredentials { HostCredentials(identities: identities, passwords: passwords) }

    public static let live = AppServices(
        hosts: HostStore.shared, identities: IdentityStore.shared, knownHosts: KnownHostStore.shared,
        passwords: KeychainKeyStore(), push: PushService.shared, appearance: AppearanceStore.shared,
        shortcuts: ShortcutGroupStore.shared, sessions: SessionStore.shared
    )
}
