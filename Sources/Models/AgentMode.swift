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

    public var isFrontier: Bool { self != .local }

    public static func signInNeeded(by agent: AgentInfo?, error text: String) -> AgentHarness? {
        guard text.contains("Not logged in"),
              let harness = agent.flatMap({ AgentHarness(rawValue: $0.harness) }),
              harness.loginCommand != nil else { return nil }
        return harness
    }

    public static let frontier: [AgentHarness] = allCases.filter(\.isFrontier)
}

public enum AgentWorkerChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixed, orchestrator

    public var id: String { rawValue }
}

public struct AgentModeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hostID: UUID?
    public var orchestrator: AgentHarness
    public var orchestratorModel: String
    public var worker: AgentHarness
    public var workerModel: String
    public var workerChoice: AgentWorkerChoice
    public var workerAllowed: [AgentHarness]
    public var workerLocalModel: String
    public var localURL: String
    public var podmanPath: String
    public var hostDirectories: [String]

    public init(
        enabled: Bool = false,
        hostID: UUID? = nil,
        orchestrator: AgentHarness = .claude,
        orchestratorModel: String = "",
        worker: AgentHarness = .claude,
        workerModel: String = "",
        workerChoice: AgentWorkerChoice = .fixed,
        workerAllowed: [AgentHarness] = [.claude],
        workerLocalModel: String = "",
        localURL: String = "http://host.containers.internal:8083/v1",
        podmanPath: String = "",
        hostDirectories: [String] = []
    ) {
        self.enabled = enabled
        self.hostID = hostID
        self.orchestrator = orchestrator
        self.orchestratorModel = orchestratorModel
        self.worker = worker
        self.workerModel = workerModel
        self.workerChoice = workerChoice
        self.workerAllowed = workerAllowed
        self.workerLocalModel = workerLocalModel
        self.localURL = localURL
        self.podmanPath = podmanPath
        self.hostDirectories = hostDirectories
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, hostID, orchestrator, orchestratorModel, worker, workerModel, localURL, podmanPath
        case workerChoice, workerAllowed, workerLocalModel, hostDirectories
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decode(Bool.self, forKey: .enabled),
            hostID: try c.decodeIfPresent(UUID.self, forKey: .hostID),
            orchestrator: try c.decode(AgentHarness.self, forKey: .orchestrator),
            orchestratorModel: try c.decode(String.self, forKey: .orchestratorModel),
            worker: try c.decode(AgentHarness.self, forKey: .worker),
            workerModel: try c.decode(String.self, forKey: .workerModel),
            workerChoice: try c.decodeIfPresent(AgentWorkerChoice.self, forKey: .workerChoice) ?? .fixed,
            workerAllowed: try c.decodeIfPresent([AgentHarness].self, forKey: .workerAllowed) ?? [.claude],
            workerLocalModel: try c.decodeIfPresent(String.self, forKey: .workerLocalModel) ?? "",
            localURL: try c.decode(String.self, forKey: .localURL),
            podmanPath: try c.decode(String.self, forKey: .podmanPath),
            hostDirectories: try c.decodeIfPresent([String].self, forKey: .hostDirectories) ?? []
        )
    }

    public static let `default` = AgentModeSettings()

    private func copy(enabled: Bool? = nil, hostID: UUID?? = nil, orchestrator: AgentHarness? = nil,
                      orchestratorModel: String? = nil, worker: AgentHarness? = nil, workerModel: String? = nil,
                      workerChoice: AgentWorkerChoice? = nil, workerAllowed: [AgentHarness]? = nil,
                      workerLocalModel: String? = nil, localURL: String? = nil, podmanPath: String? = nil,
                      hostDirectories: [String]? = nil) -> AgentModeSettings {
        AgentModeSettings(
            enabled: enabled ?? self.enabled,
            hostID: hostID ?? self.hostID,
            orchestrator: orchestrator ?? self.orchestrator,
            orchestratorModel: orchestratorModel ?? self.orchestratorModel,
            worker: worker ?? self.worker,
            workerModel: workerModel ?? self.workerModel,
            workerChoice: workerChoice ?? self.workerChoice,
            workerAllowed: workerAllowed ?? self.workerAllowed,
            workerLocalModel: workerLocalModel ?? self.workerLocalModel,
            localURL: localURL ?? self.localURL,
            podmanPath: podmanPath ?? self.podmanPath,
            hostDirectories: hostDirectories ?? self.hostDirectories
        )
    }

    public func with(enabled value: Bool) -> AgentModeSettings { copy(enabled: value) }
    public func with(hostID value: UUID?) -> AgentModeSettings { copy(hostID: .some(value), podmanPath: "") }
    public func with(orchestrator value: AgentHarness) -> AgentModeSettings { copy(orchestrator: value) }
    public func with(orchestratorModel value: String) -> AgentModeSettings { copy(orchestratorModel: value) }
    public func with(worker value: AgentHarness) -> AgentModeSettings { copy(worker: value) }
    public func with(workerModel value: String) -> AgentModeSettings { copy(workerModel: value) }
    public func with(workerChoice value: AgentWorkerChoice) -> AgentModeSettings { copy(workerChoice: value) }
    public func with(workerLocalModel value: String) -> AgentModeSettings { copy(workerLocalModel: value) }
    public func with(localURL value: String) -> AgentModeSettings { copy(localURL: value) }
    public func withPodmanPath(_ value: String) -> AgentModeSettings { copy(podmanPath: value) }
    public func with(hostDirectories value: [String]) -> AgentModeSettings { copy(hostDirectories: value) }

    public func allowing(_ harness: AgentHarness, _ allowed: Bool) -> AgentModeSettings {
        let rest = workerAllowed.filter { $0 != harness }
        let next = allowed ? rest + [harness] : rest
        return copy(workerAllowed: AgentHarness.allCases.filter(next.contains))
    }

    public var workerHarnesses: [AgentHarness] {
        workerChoice == .fixed ? [worker] : workerAllowed
    }

    public var usesLocalEndpoint: Bool {
        orchestrator == .local || workerHarnesses.contains(.local)
    }

    public var signInHarnesses: [AgentHarness] {
        AgentHarness.allCases.filter { h in
            h.loginCommand != nil && (h == orchestrator || workerHarnesses.contains(h))
        }
    }

    public var problem: String? {
        if orchestrator == .local && orchestratorModel.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Name the local model for the orchestrator."
        }
        switch workerChoice {
        case .fixed:
            if worker == .local && workerModel.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Name the local model for subagents."
            }
        case .orchestrator:
            if workerAllowed.isEmpty { return "Allow at least one kind of subagent." }
            if workerAllowed.contains(.local) && workerLocalModel.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Name the local model subagents may use."
            }
        }
        return nil
    }

    public static func hostDirectoryProblem(_ path: String, among existing: [String]) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return "Use a full path that starts with /." }
        guard trimmed.count > 1 else { return "Sharing / would expose the whole host." }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard !existing.contains(normalized) else { return "That folder is already shared." }
        return nil
    }

    public static func normalizedHostDirectory(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 1 && trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
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

public struct AgentChat: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: Int64

    public init(id: String, title: String, createdAt: Int64) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}

public struct AgentChatMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: Int64
    public let chatId: String
    public let agentId: String?
    public let author: String
    public let kind: AgentMessageKind
    public let text: String
    public let createdAt: Int64
    public let attachment: AgentAttachment?

    public init(id: Int64, chatId: String, agentId: String?, author: String, kind: AgentMessageKind, text: String,
                createdAt: Int64, attachment: AgentAttachment? = nil) {
        self.id = id
        self.chatId = chatId
        self.agentId = agentId
        self.author = author
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.attachment = attachment
    }
}

public struct AgentPendingSend: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let chatId: String
    public let text: String

    public init(id: UUID, chatId: String, text: String) {
        self.id = id
        self.chatId = chatId
        self.text = text
    }

    public static func removingEcho(of message: AgentChatMessage, from pending: [AgentPendingSend]) -> [AgentPendingSend] {
        guard message.kind == .user,
              let index = pending.firstIndex(where: { $0.chatId == message.chatId && $0.text == message.text })
        else { return pending }
        return Array(pending[..<index] + pending[(index + 1)...])
    }
}

public enum AgentStatus: String, Codable, Sendable {
    case starting, working, idle, failed, stopped
}

public enum AgentWorkStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case blocked, done
}

public enum AgentVerdict: String, Codable, Sendable {
    case pass, fail
}

public struct AgentInfo: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let chatId: String
    public let name: String
    public let role: String
    public let harness: String
    public let model: String?
    public let status: AgentStatus
    public let task: String?
    public let goal: String?
    public let workStatus: AgentWorkStatus?
    public let verification: String?
    public let verdict: AgentVerdict?
    public let verdictNote: String?
    public let container: String
    public let createdAt: Int64
    public let updatedAt: Int64

    public var isOrchestrator: Bool { role == "orchestrator" }
}

public struct AgentRequest: Codable, Equatable, Sendable {
    public let op: String
    public let since: Int64?
    public let chatId: String?
    public let text: String?
    public let agentId: String?
    public let title: String?

    init(op: String, since: Int64? = nil, chatId: String? = nil, text: String? = nil, agentId: String? = nil,
         title: String? = nil) {
        self.op = op
        self.since = since
        self.chatId = chatId
        self.text = text
        self.agentId = agentId
        self.title = title
    }

    public static func hello(since: Int64) -> AgentRequest {
        AgentRequest(op: "hello", since: since)
    }

    public static func send(chatID: String, text: String) -> AgentRequest {
        AgentRequest(op: "send", chatId: chatID, text: text)
    }

    public static func stop(agentID: String) -> AgentRequest {
        AgentRequest(op: "stop", agentId: agentID)
    }

    public static func createChat(title: String) -> AgentRequest {
        AgentRequest(op: "createChat", title: title)
    }

    public static func deleteChat(id: String) -> AgentRequest {
        AgentRequest(op: "deleteChat", chatId: id)
    }
}

public enum AgentModeEvent: Equatable, Sendable {
    case ready
    case message(AgentChatMessage)
    case agent(AgentInfo)
    case chat(AgentChat)
    case chatRemoved(String)
    case error(String)
}

extension AgentModeEvent: Decodable {
    private enum CodingKeys: String, CodingKey { case type, message, agent, chat, chatId, error }

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
        case "chat":
            self = .chat(try c.decode(AgentChat.self, forKey: .chat))
        case "chatRemoved":
            self = .chatRemoved(try c.decode(String.self, forKey: .chatId))
        case "error":
            self = .error(try c.decodeIfPresent(String.self, forKey: .error) ?? "unknown error")
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown event type \(type)")
        }
    }
}

public struct AgentTrackEntry: Equatable, Sendable {
    public let heading: String
    public let date: Date?
    public let body: String

    public init(heading: String, date: Date?, body: String) {
        self.heading = heading
        self.date = date
        self.body = body
    }

    public static func parse(_ log: String) -> [AgentTrackEntry] {
        ("\n" + log).components(separatedBy: "\n## ")
            .dropFirst()
            .compactMap { chunk in
                let parts = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let heading = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
                let body = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                guard !body.isEmpty else { return nil }
                return AgentTrackEntry(heading: heading, date: ISO8601DateFormatter().date(from: heading), body: body)
            }
    }
}
