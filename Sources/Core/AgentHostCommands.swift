import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public enum AgentHostCommands {
    public static let daemonContainer = "sshido-agents"
    public static let daemonImage = "localhost/sshido-agents:latest"
    public static let agentImage = "localhost/sshido-agent:latest"
    public static let notifySecret = "sshido-agents-notify"
    static let dataVolume = "sshido-agents-data"
    static let busVolume = "sshido-agents-bus"
    static let workspaceVolume = "sshido-agents-workspace"

    static let pathPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"

    static func q(_ s: String) -> String { TmuxSessionList.shellQuote(s) }

    public static let findPodman = "\(pathPrefix); command -v podman || true"

    static let hostClaudeHome = #"$([ "$(uname -s)" = Linux ] && [ -d "$HOME/.claude" ] && [ -f "$HOME/.claude.json" ] && printf %s "$HOME")"#

    public static func status(podman: String) -> String {
        let p = q(podman)
        let checks = [
            "echo \"daemon=$(\(p) container inspect \(daemonContainer) --format '{{.State.Status}}' 2>/dev/null || echo missing)\"",
            "echo \"daemonImage=$(\(p) image exists \(daemonImage) && echo yes || echo no)\"",
            "echo \"agentImage=$(\(p) image exists \(agentImage) && echo yes || echo no)\"",
            "echo \"socket=$(\(p) info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null)\"",
            "echo \"notify=$(\(p) secret exists \(notifySecret) && echo yes || echo no)\"",
        ]
        return checks.joined(separator: "; ")
    }

    public static func setNotifySecret(podman: String, url: String) -> String {
        "printf %s \(q(url)) | \(q(podman)) secret create --replace \(notifySecret) -"
    }

    public static func startDaemon(podman: String, socketPath: String, settings: AgentModeSettings, hostName: String, notify: Bool) -> String {
        let socket = socketPath.hasPrefix("unix://") ? String(socketPath.dropFirst("unix://".count)) : socketPath
        let env: [(String, String)] = [
            ("SSHIDO_AGENT_IMAGE", agentImage),
            ("SSHIDO_ORCHESTRATOR", settings.orchestrator.rawValue),
            ("SSHIDO_ORCHESTRATOR_MODEL", settings.orchestratorModel),
            ("SSHIDO_WORKER_CHOICE", settings.workerChoice.rawValue),
            ("SSHIDO_WORKER_HARNESS", settings.worker.rawValue),
            ("SSHIDO_WORKER_MODEL", settings.workerModel),
            ("SSHIDO_WORKER_HARNESSES", settings.workerAllowed.map(\.rawValue).joined(separator: ",")),
            ("SSHIDO_WORKER_LOCAL_MODEL", settings.workerLocalModel),
            ("SSHIDO_LOCAL_URL", settings.localURL),
            ("SSHIDO_HOST_DIRS", hostDirsJSON(settings.hostDirectories)),
            ("SSHIDO_HOST_NAME", hostName),
        ]
        let envFlags = env.map { "-e \(q("\($0.0)=\($0.1)"))" }.joined(separator: " ")
        return [
            q(podman), "run -d --name \(daemonContainer) --restart always --user 0 --security-opt label=disable",
            "-v \(q("\(socket):/run/podman.sock"))",
            "-v \(busVolume):/bus -v \(dataVolume):/data -v \(workspaceVolume):/workspace",
            notify ? "--secret \(notifySecret),type=env,target=SSHIDO_NOTIFY_URL" : nil,
            envFlags, "-e \"SSHIDO_HOST_CLAUDE_HOME=\(hostClaudeHome)\"", daemonImage, "daemon",
        ].compactMap { $0 }.joined(separator: " ")
    }

    static func hostDirsJSON(_ dirs: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(dirs) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func replaceDaemon(podman: String, socketPath: String, settings: AgentModeSettings, hostName: String, notify: Bool) -> String {
        "\(q(podman)) rm -f \(daemonContainer) >/dev/null && "
            + startDaemon(podman: podman, socketPath: socketPath, settings: settings, hostName: hostName, notify: notify)
    }

    public static func restartDaemon(podman: String) -> String {
        "\(q(podman)) start \(daemonContainer)"
    }

    public static func reset(podman: String) -> String {
        let p = q(podman)
        return "\(p) rm -f \(daemonContainer) $(\(p) ps -aq --filter label=sshido.agents=1) >/dev/null 2>&1; "
            + "\(p) volume rm -f \(dataVolume) \(busVolume) >/dev/null 2>&1; echo reset"
    }

    public static func attach(podman: String) -> String {
        "\(q(podman)) exec -i \(daemonContainer) /usr/local/bin/sshido-agents attach"
    }

    public static func file(podman: String, messageID: Int64) -> String {
        "\(q(podman)) exec \(daemonContainer) /usr/local/bin/sshido-agents file \(messageID)"
    }

    public static func log(podman: String, agentID: String) -> String {
        "\(q(podman)) exec \(daemonContainer) /usr/local/bin/sshido-agents log \(q(agentID))"
    }

    public static let desktopPort = 6080

    public static func desktopServe(podman: String, container: String) -> String {
        "\(q(podman)) start \(q(container)) >/dev/null && \(q(podman)) exec -u agent \(q(container)) desktop serve"
    }

    public static func desktopHostPort(podman: String, container: String) -> String {
        "\(q(podman)) port \(q(container)) \(desktopPort)/tcp"
    }

    public static func parseHostPort(_ output: String) -> Int? {
        output.split(separator: "\n")
            .compactMap { line in line.split(separator: ":").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
            .first { $0 > 0 && $0 < 65536 }
    }

    public static func listLocalModels(podman: String, endpoint: String) -> String {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/models"
        return "\(q(podman)) run --rm --entrypoint curl \(agentImage) -fsS -m 8 \(q(url))"
    }

    public static func parseModelList(_ output: String) -> [String] {
        struct Listing: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: Data(output.utf8)) else { return [] }
        return Array(Set(listing.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    public static func peek(podman: String, container: String) -> String {
        "\(q(podman)) exec -it \(q(container)) bash"
    }

    public static func login(podman: String, harness: AgentHarness) -> String? {
        guard let command = harness.loginCommand else { return nil }
        let dir = harness.loginDirectory
        let inner = "chown agent:agent \(dir) && exec runuser -u agent -- env HOME=/home/agent "
            + "CLAUDE_CONFIG_DIR=/home/agent/.claude \(command)"
        let ownVolume = "\(q(podman)) run -it --rm --user 0 -v \(harness.loginVolume):\(dir) \(agentImage) sh -c \(q(inner))"
        guard harness == .claude else { return ownVolume }
        let hostConfig = "\(q(podman)) run -it --rm --user agent --userns keep-id:uid=1001,gid=1001 --security-opt label=disable "
            + #"-v "$H/.claude:$H/.claude" -v "$H/.claude.json:$H/.claude/.claude.json" -e "CLAUDE_CONFIG_DIR=$H/.claude" "#
            + "\(agentImage) \(command)"
        return "H=\"\(hostClaudeHome)\"; if [ -n \"$H\" ]; then \(hostConfig); else \(ownVolume); fi"
    }
}

public struct AgentHostStatus: Equatable, Sendable {
    public enum Daemon: Equatable, Sendable {
        case missing
        case running
        case stopped(String)
    }

    public let daemon: Daemon
    public let daemonImage: Bool
    public let agentImage: Bool
    public let socketPath: String
    public let notifySecret: Bool

    public var ready: Bool { daemon == .running }

    public static func parse(_ output: String) -> AgentHostStatus {
        let pairs = output.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        let values = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        let daemonState = values["daemon"] ?? "missing"
        let daemon: Daemon = daemonState == "missing" || daemonState.isEmpty
            ? .missing
            : (daemonState == "running" ? .running : .stopped(daemonState))
        return AgentHostStatus(
            daemon: daemon,
            daemonImage: values["daemonImage"] == "yes",
            agentImage: values["agentImage"] == "yes",
            socketPath: values["socket"] ?? "",
            notifySecret: values["notify"] == "yes"
        )
    }
}
