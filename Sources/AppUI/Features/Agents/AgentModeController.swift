#if canImport(UIKit)
import Foundation
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

enum HostAuth {
    static func resolve(for host: RemoteHost) async throws -> SSHAuth {
        switch host.authMethod {
        case .password:
            return .password(try KeychainKeyStore().loadPassword(hostID: host.id))
        case .key:
            guard let identityID = host.identityID else {
                throw SSHError.invalidKey("host has no key attached (authMethod=.key)")
            }
            let pem = try await IdentityStore.shared.loadPEM(for: identityID)
            return .privateKeyPEM(pem, passphrase: nil)
        }
    }
}

@MainActor
final class AgentModeController: ObservableObject {
    static let shared = AgentModeController()

    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    enum Creation: Equatable {
        case idle
        case waiting(known: Set<String>)
        case created(String)
        case failed(String)
    }

    @Published private(set) var settings: AgentModeSettings
    @Published private(set) var status: AgentHostStatus?
    @Published private(set) var setupLog: [String] = []
    @Published private(set) var busy = false
    @Published private(set) var messages: [AgentChatMessage] = []
    @Published private(set) var agents: [AgentInfo] = []
    @Published private(set) var connection: Connection = .disconnected
    @Published private(set) var chats: [AgentChat] = []
    @Published private(set) var pending: [AgentPendingSend] = []
    @Published private(set) var historyLoaded = false
    @Published private(set) var creation: Creation = .idle
    @Published var notice: String?
    @Published private(set) var attachmentFiles: [Int64: URL] = [:]
    @Published private(set) var localModels: [String] = []
    @Published private(set) var loadingLocalModels = false
    private var attachmentLoads: [Int64: Task<URL, Error>] = [:]
    private var desktopTunnel: OAuthTunnel?
    private let downloads = SerialGate()

    private let store = AgentModeSettingsStore()
    private var bridge: AgentBridge?
    private var streamTask: Task<Void, Never>?
    private var holders = 0
    private var releaseTask: Task<Void, Never>?

    private init() {
        self.settings = AgentModeSettingsStore().load()
    }

    var lastMessageID: Int64 { messages.map(\.id).filter { $0 > 0 }.max() ?? 0 }

    func update(_ change: (AgentModeSettings) -> AgentModeSettings) {
        let next = change(settings)
        do {
            try store.save(next)
            settings = next
        } catch {
            log("Could not save agent mode settings: \(error.localizedDescription)")
        }
    }

    func host() async -> RemoteHost? {
        guard let id = settings.hostID else { return nil }
        return await HostStore.shared.all().first { $0.id == id }
    }

    private func log(_ line: String) {
        setupLog = setupLog.suffix(40) + [line]
    }

    private func makeBridge() async throws -> AgentBridge {
        if let bridge { return bridge }
        guard let host = await host() else { throw AgentModeError.noHost }
        let auth = try await HostAuth.resolve(for: host)
        let channel = await SessionStore.shared.metricsChannel(for: host, auth: auth)
        let made = AgentBridge(channel: channel)
        bridge = made
        return made
    }

    private func podman(using bridge: AgentBridge) async throws -> String {
        if !settings.podmanPath.isEmpty { return settings.podmanPath }
        let found = try await bridge.run(AgentHostCommands.findPodman).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !found.isEmpty else { throw AgentModeError.noPodman }
        update { $0.withPodmanPath(found) }
        return found
    }

    func checkHost() async {
        await runSetup { bridge in
            let podman = try await self.podman(using: bridge)
            let parsed = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            self.status = parsed
            self.log(Self.describe(parsed, podman: podman))
        }
    }

    func setUpHost() async {
        await runSetup { bridge in
            let podman = try await self.podman(using: bridge)
            let before = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            guard before.daemonImage, before.agentImage else { throw AgentModeError.missingImages }
            let notify = try await self.ensureNotifySecret(bridge: bridge, podman: podman)
            try await self.ensureDaemon(bridge: bridge, podman: podman, status: before, notify: notify)
            let after = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            self.status = after
            self.log(Self.describe(after, podman: podman))
        }
    }

    func resetHost() async {
        await runSetup { bridge in
            let podman = try await self.podman(using: bridge)
            self.stopChat()
            _ = try await bridge.run(AgentHostCommands.reset(podman: podman))
            self.messages = []
            self.agents = []
            self.chats = []
            self.pending = []
            self.log("Removed the agents and chat history. Set up the host again to start fresh.")
        }
    }

    func applySettings() async {
        await runSetup { bridge in
            let podman = try await self.podman(using: bridge)
            let before = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            guard before.daemonImage, before.agentImage else { throw AgentModeError.missingImages }
            guard let host = await self.host() else { throw AgentModeError.noHost }
            let notify = try await self.ensureNotifySecret(bridge: bridge, podman: podman)
            self.log("Restarting the agents daemon with the current settings. Running turns are interrupted.")
            let command = before.daemon == .missing
                ? AgentHostCommands.startDaemon(podman: podman, socketPath: before.socketPath, settings: self.settings,
                                                hostName: host.name, notify: notify)
                : AgentHostCommands.replaceDaemon(podman: podman, socketPath: before.socketPath, settings: self.settings,
                                                  hostName: host.name, notify: notify)
            _ = try await bridge.run(command)
            let after = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            self.status = after
            self.log(Self.describe(after, podman: podman))
            self.reconnectIfHeld()
        }
    }

    private func reconnectIfHeld() {
        stopChat()
        if holders > 0 { startChat() }
    }

    private func ensureNotifySecret(bridge: AgentBridge, podman: String) async throws -> Bool {
        guard let url = await PushService.shared.subscription?.notifyURL, !url.isEmpty else {
            log("No push subscription: agents will reply in the chat, without notifications.")
            return false
        }
        _ = try await bridge.run(AgentHostCommands.setNotifySecret(podman: podman, url: url))
        return true
    }

    private func ensureDaemon(bridge: AgentBridge, podman: String, status: AgentHostStatus, notify: Bool) async throws {
        switch status.daemon {
        case .running:
            return
        case .stopped:
            log("Restarting the agents daemon.")
            _ = try await bridge.run(AgentHostCommands.restartDaemon(podman: podman))
        case .missing:
            guard let host = await host() else { throw AgentModeError.noHost }
            log("Starting the agents daemon.")
            _ = try await bridge.run(AgentHostCommands.startDaemon(
                podman: podman, socketPath: status.socketPath, settings: settings, hostName: host.name, notify: notify))
        }
    }

    private func runSetup(_ work: @escaping (AgentBridge) async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await work(try await makeBridge())
        } catch {
            log("Failed: \(Self.message(for: error))")
            await dropBridge()
        }
    }

    private static func describe(_ s: AgentHostStatus, podman: String) -> String {
        let daemon: String
        switch s.daemon {
        case .running: daemon = "running"
        case .stopped(let state): daemon = "stopped (\(state))"
        case .missing: daemon = "not created"
        }
        return "Podman at \(podman). Daemon \(daemon). Images: daemon \(s.daemonImage ? "yes" : "no"), agent \(s.agentImage ? "yes" : "no"). Notifications \(s.notifySecret ? "on" : "off")."
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func dropBridge() async {
        let old = bridge
        bridge = nil
        await old?.disconnect()
    }

    func hold() {
        holders += 1
        releaseTask?.cancel()
        releaseTask = nil
        startChat()
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.holders == 0 else { return }
            self.stopChat()
        }
    }

    func startChat() {
        guard streamTask == nil else { return }
        connection = .connecting
        historyLoaded = false
        streamTask = Task { [weak self] in
            await self?.runChat()
        }
    }

    func stopChat() {
        streamTask?.cancel()
        streamTask = nil
        connection = .disconnected
    }

    private func runChat() async {
        do {
            let bridge = try await makeBridge()
            let podman = try await podman(using: bridge)
            let before = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
            if case .stopped = before.daemon {
                _ = try await bridge.run(AgentHostCommands.restartDaemon(podman: podman))
            }
            guard before.daemon != .missing else { throw AgentModeError.notSetUp }
            for try await output in await bridge.events(podman: podman, since: lastMessageID) {
                apply(output)
            }
            connection = .failed("The connection to the agents ended. Pull to reconnect.")
        } catch is CancellationError {
            connection = .disconnected
        } catch {
            connection = .failed(Self.message(for: error))
            await dropBridge()
        }
        streamTask = nil
    }

    private func apply(_ output: AgentLineDecoder.Output) {
        switch output {
        case .event(.ready):
            connection = .connected
            historyLoaded = true
        case .event(.message(let m)):
            guard !messages.contains(where: { $0.id == m.id }) else { return }
            messages = messages + [m]
            pending = AgentPendingSend.removingEcho(of: m, from: pending)
        case .event(.agent(let a)):
            agents = (agents.filter { $0.id != a.id } + [a]).sorted { $0.createdAt < $1.createdAt }
        case .event(.chat(let c)):
            chats = (chats.filter { $0.id != c.id } + [c]).sorted { $0.createdAt < $1.createdAt }
            creation = Self.creation(creation, seeing: c.id)
        case .event(.chatRemoved(let id)):
            chats = chats.filter { $0.id != id }
            messages = messages.filter { $0.chatId != id }
            agents = agents.filter { $0.chatId != id }
            pending = pending.filter { $0.chatId != id }
        case .event(.error(let text)):
            report(text)
        case .undecodable(let line):
            log("Ignored a line from the host that was not an agent event: \(line.prefix(120))")
        }
    }

    static func creation(_ state: Creation, seeing chatID: String) -> Creation {
        guard case .waiting(let known) = state, !known.contains(chatID) else { return state }
        return .created(chatID)
    }

    private func report(_ text: String) {
        guard case .waiting = creation else {
            notice = text
            return
        }
        creation = .failed(text)
    }

    func chat(_ id: String) -> AgentChat? { chats.first { $0.id == id } }
    func messages(in chatID: String) -> [AgentChatMessage] { messages.filter { $0.chatId == chatID } }
    func agents(in chatID: String) -> [AgentInfo] { agents.filter { $0.chatId == chatID } }
    func pending(in chatID: String) -> [AgentPendingSend] { pending.filter { $0.chatId == chatID } }

    func send(_ text: String, to chatID: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let bridge, connection == .connected else { return false }
        let entry = AgentPendingSend(id: UUID(), chatId: chatID, text: trimmed)
        pending = pending + [entry]
        do {
            try await bridge.send(.send(chatID: chatID, text: trimmed))
            return true
        } catch {
            pending = pending.filter { $0.id != entry.id }
            connection = .failed(Self.message(for: error))
            return false
        }
    }

    func createChat(_ request: AgentRequest) async {
        guard let bridge, connection == .connected else {
            creation = .failed("Not connected to the agents.")
            return
        }
        creation = .waiting(known: Set(chats.map(\.id)))
        do {
            try await bridge.send(request)
        } catch {
            creation = .failed(Self.message(for: error))
            connection = .failed(Self.message(for: error))
        }
    }

    func resetCreation() {
        creation = .idle
    }

    func deleteChat(_ id: String) async {
        guard let bridge, connection == .connected else {
            notice = "Not connected to the agents."
            return
        }
        do {
            try await bridge.send(.deleteChat(id: id))
        } catch {
            connection = .failed(Self.message(for: error))
        }
    }

    func stop(agent: AgentInfo) async {
        guard let bridge else { return }
        do {
            try await bridge.send(.stop(agentID: agent.id))
        } catch {
            connection = .failed(Self.message(for: error))
        }
    }

    func attachmentURL(for message: AgentChatMessage) async throws -> URL {
        if let url = attachmentFiles[message.id] { return url }
        if let running = attachmentLoads[message.id] { return try await running.value }
        let task = Task { try await self.downloadAttachment(message) }
        attachmentLoads = attachmentLoads.merging([message.id: task]) { $1 }
        defer { attachmentLoads = attachmentLoads.filter { $0.key != message.id } }
        let url = try await task.value
        attachmentFiles = attachmentFiles.merging([message.id: url]) { $1 }
        return url
    }

    private func downloadAttachment(_ message: AgentChatMessage) async throws -> URL {
        guard let attachment = message.attachment else { throw AgentModeError.noAttachment }
        let dir = try attachmentDirectory()
        let safeName = attachment.name.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent("\(message.id)-\(safeName)")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let bridge = try await makeBridge()
        let podman = try await podman(using: bridge)
        let command = AgentHostCommands.file(podman: podman, messageID: message.id)
        let data = try await downloads.run { try await bridge.runData(command) }
        guard Int64(data.count) == attachment.size else {
            throw AgentModeError.incompleteFile(expected: attachment.size, got: Int64(data.count))
        }
        try data.write(to: file, options: .atomic)
        return file
    }

    private func attachmentDirectory() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = caches.appendingPathComponent("agent-files/\(settings.hostID?.uuidString ?? "none")", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refreshLocalModels() async {
        guard settings.hostID != nil, !loadingLocalModels else { return }
        loadingLocalModels = true
        defer { loadingLocalModels = false }
        do {
            let bridge = try await makeBridge()
            let podman = try await podman(using: bridge)
            let output = try await bridge.run(AgentHostCommands.listLocalModels(podman: podman, endpoint: settings.localURL))
            localModels = AgentHostCommands.parseModelList(output)
            if localModels.isEmpty { log("The local endpoint listed no models.") }
        } catch {
            localModels = []
            log("Could not list local models: \(Self.message(for: error))")
        }
    }

    func trackRecord(of agent: AgentInfo) async throws -> String {
        let bridge = try await makeBridge()
        let podman = try await podman(using: bridge)
        return try await bridge.run(AgentHostCommands.log(podman: podman, agentID: agent.id))
    }

    func openDesktop(of agent: AgentInfo) async throws -> URL {
        let bridge = try await makeBridge()
        let podman = try await podman(using: bridge)
        let password = try await bridge.run(AgentHostCommands.desktopServe(podman: podman, container: agent.container))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count == 8, password.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw AgentModeError.desktopUnavailable(password.isEmpty ? "no password came back" : String(password.prefix(200)))
        }
        let portOutput = try await bridge.run(AgentHostCommands.desktopHostPort(podman: podman, container: agent.container))
        guard let port = AgentHostCommands.parseHostPort(portOutput) else {
            throw AgentModeError.desktopNotPublished
        }
        await closeDesktop()
        desktopTunnel = try await bridge.tunnel(toLoopbackPort: port)
        guard let url = URL(string: "http://127.0.0.1:\(port)/vnc.html?autoconnect=1&resize=scale&password=\(password)") else {
            throw AgentModeError.desktopNotPublished
        }
        return url
    }

    func closeDesktop() async {
        let old = desktopTunnel
        desktopTunnel = nil
        await old?.stop()
    }

    func openTerminal(typing command: String, title: String, router: AppRouter) async {
        guard let host = await host() else { return }
        do {
            let auth = try await HostAuth.resolve(for: host)
            let session = await SessionStore.shared.openSession(for: host, auth: auth, title: title)
            router.pushSession(session, host: host)
            let channel = await SessionStore.shared.ensureChannel(for: session, host: host, auth: auth)
            try await channel.send(Array((command + "\r").utf8))
        } catch {
            log("Could not open a terminal: \(Self.message(for: error))")
        }
    }

    func peek(_ agent: AgentInfo, router: AppRouter) async {
        guard !settings.podmanPath.isEmpty else { return }
        await openTerminal(typing: AgentHostCommands.peek(podman: settings.podmanPath, container: agent.container),
                           title: "peek \(agent.name)", router: router)
    }

    func signIn(_ harness: AgentHarness, router: AppRouter) async {
        guard !settings.podmanPath.isEmpty,
              let command = AgentHostCommands.login(podman: settings.podmanPath, harness: harness) else {
            notice = "Run Check host in Settings → Agents before signing in to \(harness.label)."
            log("Could not sign in to \(harness.label): run Check host first so the app knows where Podman is.")
            return
        }
        await openTerminal(typing: command, title: "sign in \(harness.label)", router: router)
    }
}

enum AgentModeError: LocalizedError {
    case noHost, noPodman, missingImages, notSetUp, noAttachment, desktopNotPublished
    case incompleteFile(expected: Int64, got: Int64)
    case desktopUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noHost: return "Choose the host that runs your agents."
        case .noPodman: return "Podman is not installed on this host. Install it (brew install podman, or your Linux package manager) and try again."
        case .missingImages: return "The agent images are not on this host yet. Build them from server/sshido-agents (see its README)."
        case .notSetUp: return "Agent mode is not set up on this host yet. Open Settings → Agent mode → Set up host."
        case .noAttachment: return "This message has no file."
        case .incompleteFile(let expected, let got): return "The file arrived incomplete (\(got) of \(expected) bytes). Try again."
        case .desktopUnavailable(let detail): return "The agent's desktop did not start: \(detail)"
        case .desktopNotPublished: return "This agent's container has no desktop port yet. Tap Apply settings in Settings → Agent mode to set it up again."
        }
    }
}
#endif
