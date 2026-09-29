import Foundation

public enum AgentHarness: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex, gemini, grok, local

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .grok: return "Grok"
        case .local: return "Local model"
        }
    }

    public var loginVolume: String {
        switch self {
        case .claude: return "sshido-auth-claude"
        case .codex, .local: return "sshido-auth-codex"
        case .gemini: return "sshido-auth-gemini"
        case .grok: return "sshido-auth-grok"
        }
    }

    public var loginDirectory: String {
        switch self {
        case .claude: return "/home/agent/.claude"
        case .codex, .local: return "/home/agent/.codex"
        case .gemini: return "/home/agent/.gemini"
        case .grok: return "/home/agent/.grok"
        }
    }

    public var loginCommand: String? {
        switch self {
        case .claude: return "claude auth login --claudeai"
        case .codex: return "codex login --device-auth"
        case .gemini: return "gemini"
        case .grok: return "grok login --device-auth"
        case .local: return nil
        }
    }
}

public struct AgentModeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hostID: UUID?
    public var orchestrator: AgentHarness
    public var orchestratorModel: String
    public var worker: AgentHarness
    public var workerModel: String
    public var localURL: String
    public var podmanPath: String

    public init(
        enabled: Bool = false,
        hostID: UUID? = nil,
        orchestrator: AgentHarness = .claude,
        orchestratorModel: String = "",
        worker: AgentHarness = .claude,
        workerModel: String = "",
        localURL: String = "http://host.containers.internal:8083/v1",
        podmanPath: String = ""
    ) {
        self.enabled = enabled
        self.hostID = hostID
        self.orchestrator = orchestrator
        self.orchestratorModel = orchestratorModel
        self.worker = worker
        self.workerModel = workerModel
        self.localURL = localURL
        self.podmanPath = podmanPath
    }

    public static let `default` = AgentModeSettings()

    private func copy(enabled: Bool? = nil, hostID: UUID?? = nil, orchestrator: AgentHarness? = nil,
                      orchestratorModel: String? = nil, worker: AgentHarness? = nil, workerModel: String? = nil,
                      localURL: String? = nil, podmanPath: String? = nil) -> AgentModeSettings {
        AgentModeSettings(
            enabled: enabled ?? self.enabled,
            hostID: hostID ?? self.hostID,
            orchestrator: orchestrator ?? self.orchestrator,
            orchestratorModel: orchestratorModel ?? self.orchestratorModel,
            worker: worker ?? self.worker,
            workerModel: workerModel ?? self.workerModel,
            localURL: localURL ?? self.localURL,
            podmanPath: podmanPath ?? self.podmanPath
        )
    }

    public func with(enabled value: Bool) -> AgentModeSettings { copy(enabled: value) }
    public func with(hostID value: UUID?) -> AgentModeSettings { copy(hostID: .some(value), podmanPath: "") }
    public func with(orchestrator value: AgentHarness) -> AgentModeSettings { copy(orchestrator: value) }
    public func with(orchestratorModel value: String) -> AgentModeSettings { copy(orchestratorModel: value) }
    public func with(worker value: AgentHarness) -> AgentModeSettings { copy(worker: value) }
    public func with(workerModel value: String) -> AgentModeSettings { copy(workerModel: value) }
    public func with(localURL value: String) -> AgentModeSettings { copy(localURL: value) }
    public func withPodmanPath(_ value: String) -> AgentModeSettings { copy(podmanPath: value) }
}

public enum AgentMessageKind: String, Codable, Sendable {
    case user, reply, progress, done
    case needsInput = "needs_input"
    case error
    case file
}

public struct AgentAttachment: Codable, Equatable, Sendable {
    public let name: String
    public let mime: String
    public let size: Int64

    public init(name: String, mime: String, size: Int64) {
        self.name = name
        self.mime = mime
        self.size = size
    }

    public var isImage: Bool { mime.hasPrefix("image/") }
    public var isVideo: Bool { mime.hasPrefix("video/") }
}

public struct AgentChatMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: Int64
    public let agentId: String?
    public let author: String
    public let kind: AgentMessageKind
    public let text: String
    public let createdAt: Int64
    public let attachment: AgentAttachment?

    public init(id: Int64, agentId: String?, author: String, kind: AgentMessageKind, text: String, createdAt: Int64,
                attachment: AgentAttachment? = nil) {
        self.id = id
        self.agentId = agentId
        self.author = author
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.attachment = attachment
    }
}

public enum AgentStatus: String, Codable, Sendable {
    case starting, working, idle, failed, stopped
}

public struct AgentInfo: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let harness: String
    public let model: String?
    public let status: AgentStatus
    public let task: String?
    public let container: String
    public let createdAt: Int64
    public let updatedAt: Int64

    public var isOrchestrator: Bool { role == "orchestrator" }
}

public struct AgentRequest: Codable, Equatable, Sendable {
    public let op: String
    public let since: Int64?
    public let text: String?
    public let agentId: String?

    public static func hello(since: Int64) -> AgentRequest {
        AgentRequest(op: "hello", since: since, text: nil, agentId: nil)
    }

    public static func send(_ text: String) -> AgentRequest {
        AgentRequest(op: "send", since: nil, text: text, agentId: nil)
    }

    public static func stop(agentID: String) -> AgentRequest {
        AgentRequest(op: "stop", since: nil, text: nil, agentId: agentID)
    }
}

public enum AgentModeEvent: Equatable, Sendable {
    case ready
    case message(AgentChatMessage)
    case agent(AgentInfo)
    case error(String)
}

extension AgentModeEvent: Decodable {
    private enum CodingKeys: String, CodingKey { case type, message, agent, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ready":
            self = .ready
        case "message":
            self = .message(try c.decode(AgentChatMessage.self, forKey: .message))
        case "agent":
            self = .agent(try c.decode(AgentInfo.self, forKey: .agent))
        case "error":
            self = .error(try c.decodeIfPresent(String.self, forKey: .error) ?? "unknown error")
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown event type \(type)")
        }
    }
}
