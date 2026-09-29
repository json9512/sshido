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

    @Published private(set) var settings: AgentModeSettings
    @Published private(set) var status: AgentHostStatus?
    @Published private(set) var setupLog: [String] = []
    @Published private(set) var busy = false
    @Published private(set) var messages: [AgentChatMessage] = []
    @Published private(set) var agents: [AgentInfo] = []
    @Published private(set) var connection: Connection = .disconnected

    private let store = AgentModeSettingsStore()
    private var bridge: AgentBridge?
    private var streamTask: Task<Void, Never>?

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
            self.log("Removed the agents and chat history. Set up the host again to start fresh.")
        }
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

    func startChat() {
        guard streamTask == nil else { return }
        connection = .connecting
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
        case .event(.message(let m)):
            guard !messages.contains(where: { $0.id == m.id }) else { return }
            messages = messages + [m]
        case .event(.agent(let a)):
            agents = (agents.filter { $0.id != a.id } + [a]).sorted { $0.createdAt < $1.createdAt }
        case .event(.error(let text)):
            messages = messages + [AgentChatMessage(id: -Int64(messages.count + 1), agentId: nil, author: "sshido",
                                                    kind: .error, text: text, createdAt: Int64(Date().timeIntervalSince1970 * 1000))]
        case .undecodable(let line):
            log("Ignored a line from the host that was not an agent event: \(line.prefix(120))")
        }
    }

    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let bridge, connection == .connected else { return false }
        do {
            try await bridge.send(.send(trimmed))
            return true
        } catch {
            connection = .failed(Self.message(for: error))
            return false
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
              let command = AgentHostCommands.login(podman: settings.podmanPath, harness: harness) else { return }
        await openTerminal(typing: command, title: "sign in \(harness.label)", router: router)
    }
}

enum AgentModeError: LocalizedError {
    case noHost, noPodman, missingImages, notSetUp

    var errorDescription: String? {
        switch self {
        case .noHost: return "Choose the host that runs your agents."
        case .noPodman: return "Podman is not installed on this host. Install it (brew install podman, or your Linux package manager) and try again."
        case .missingImages: return "The agent images are not on this host yet. Build them from server/sshido-agents (see its README)."
        case .notSetUp: return "Agent mode is not set up on this host yet. Open Settings → Agent mode → Set up host."
        }
    }
}
#endif
