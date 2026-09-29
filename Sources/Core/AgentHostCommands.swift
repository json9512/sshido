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

    static let pathPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"

    static func q(_ s: String) -> String { TmuxSessionList.shellQuote(s) }

    public static let findPodman = "\(pathPrefix); command -v podman || true"

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
            ("SSHIDO_WORKER_HARNESS", settings.worker.rawValue),
            ("SSHIDO_WORKER_MODEL", settings.workerModel),
            ("SSHIDO_LOCAL_URL", settings.localURL),
            ("SSHIDO_HOST_NAME", hostName),
        ]
        let envFlags = env.map { "-e \(q("\($0.0)=\($0.1)"))" }.joined(separator: " ")
        return [
            q(podman), "run -d --name \(daemonContainer) --restart always --user 0 --security-opt label=disable",
            "-v \(q("\(socket):/run/podman.sock"))",
            "-v \(busVolume):/bus -v \(dataVolume):/data",
            notify ? "--secret \(notifySecret),type=env,target=SSHIDO_NOTIFY_URL" : nil,
            envFlags, daemonImage, "daemon",
        ].compactMap { $0 }.joined(separator: " ")
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

    public static func peek(podman: String, container: String) -> String {
        "\(q(podman)) exec -it \(q(container)) bash"
    }

    public static func login(podman: String, harness: AgentHarness) -> String? {
        guard let command = harness.loginCommand else { return nil }
        let dir = harness.loginDirectory
        let inner = "chown agent:agent \(dir) && exec runuser -u agent -- env HOME=/home/agent "
            + "CLAUDE_CONFIG_DIR=/home/agent/.claude \(command)"
        return "\(q(podman)) run -it --rm --user 0 -v \(harness.loginVolume):\(dir) \(agentImage) sh -c \(q(inner))"
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
