import Foundation

public enum HostAuthMethod: String, Codable, Sendable, Hashable {
    case key
    case password
}

public struct RemoteHost: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var identityID: UUID?
    public var authMethod: HostAuthMethod
    public var useMosh: Bool
    public var useTmux: Bool
    public var tmuxSession: String
    public var agentProfileID: UUID?
    public var forceCompactAgent: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        identityID: UUID? = nil,
        authMethod: HostAuthMethod = .key,
        useMosh: Bool = false,
        useTmux: Bool = true,
        tmuxSession: String = "sshido",
        agentProfileID: UUID? = nil,
        forceCompactAgent: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.identityID = identityID
        self.authMethod = authMethod
        self.useMosh = useMosh
        self.useTmux = useTmux
        self.tmuxSession = tmuxSession
        self.agentProfileID = agentProfileID
        self.forceCompactAgent = forceCompactAgent
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, username, identityID, authMethod
        case useMosh, useTmux, tmuxSession, agentProfileID, forceCompactAgent
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(identityID, forKey: .identityID)
        try c.encode(authMethod, forKey: .authMethod)
        try c.encode(useMosh, forKey: .useMosh)
        try c.encode(useTmux, forKey: .useTmux)
        try c.encode(tmuxSession, forKey: .tmuxSession)
        try c.encodeIfPresent(agentProfileID, forKey: .agentProfileID)
        try c.encode(forceCompactAgent, forKey: .forceCompactAgent)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.hostname = try c.decode(String.self, forKey: .hostname)
        self.port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        self.username = try c.decode(String.self, forKey: .username)
        self.identityID = try c.decodeIfPresent(UUID.self, forKey: .identityID)
        self.authMethod = try c.decodeIfPresent(HostAuthMethod.self, forKey: .authMethod) ?? .key
        self.useMosh = try c.decodeIfPresent(Bool.self, forKey: .useMosh) ?? false
        self.useTmux = try c.decodeIfPresent(Bool.self, forKey: .useTmux) ?? true
        self.tmuxSession = try c.decodeIfPresent(String.self, forKey: .tmuxSession) ?? "sshido"
        self.agentProfileID = try c.decodeIfPresent(UUID.self, forKey: .agentProfileID)
        self.forceCompactAgent = try c.decodeIfPresent(Bool.self, forKey: .forceCompactAgent) ?? true
    }
}
