import Foundation

public struct RemoteTmuxSession: Hashable, Sendable, Identifiable {
    public let sessionID: String
    public let name: String
    public let windows: Int
    public let createdAt: Date
    public let attached: Bool
    public var id: String { sessionID }

    public init(sessionID: String, name: String, windows: Int, createdAt: Date, attached: Bool) {
        self.sessionID = sessionID
        self.name = name
        self.windows = windows
        self.createdAt = createdAt
        self.attached = attached
    }
}

public enum TmuxRenameResult: Equatable, Sendable {
    // tmux rewrites "." and ":" to "_" and still reports success, so this carries the
    // name the server settled on, not the one that was asked for.
    case renamed(String)
    case failed(String)
}

public enum TmuxAttachTarget: Equatable, Sendable {
    case attach(String)
    case noTmux
}

public enum TmuxSessionList {
    static let candidatePaths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
        "/bin/tmux",
        "/opt/local/bin/tmux",
        "/snap/bin/tmux",
        "$HOME/.local/bin/tmux",
        "/usr/pkg/bin/tmux",
        "/data/data/com.termux/files/usr/bin/tmux",
    ]

    static let renameMarker = "SSHIDO_RENAMED:"
    static let attachMarker = "SSHIDO_ATTACH:"

    // Login shell first so tmux resolves on the interactive session's PATH; the probe
    // covers shells that reject `-lc`. Trailing `true` keeps exit 0 — Citadel throws otherwise.
    public static var resolveCommand: String {
        let probes = candidatePaths.map { "\"\($0)\"" }.joined(separator: " ")
        return "${SHELL:-/bin/sh} -lc 'command -v tmux' 2>/dev/null || "
            + "for p in \(probes); do [ -x \"$p\" ] && { echo \"$p\"; break; }; done; true"
    }

    public static func parseResolvedPath(_ output: String) -> String? {
        guard let line = output.split(separator: "\n").first(where: {
            $0.hasPrefix("/") && !$0.contains(" ")
        }) else { return nil }
        return String(line)
    }

    public static func sessionName(prefix: String, sessionID: UUID) -> String {
        let base = prefix.isEmpty ? "sshido" : prefix
        return "\(base)-\(sessionID.uuidString.prefix(8))"
    }

    public static func listCommand(tmuxPath: String) -> String {
        let quoted = shellQuote(tmuxPath)
        return "\(quoted) ls -F '#{session_id}:#{session_created}:#{session_windows}:#{session_attached}:#{session_name}' 2>/dev/null; true"
    }

    public static func killCommand(tmuxPath: String, target: String) -> String {
        "\(shellQuote(tmuxPath)) kill-session -t \(shellQuote(target)) 2>/dev/null; true"
    }

    // Create-then-attach rather than `new -A`, so `mouse` is set before the client
    // attaches. `set -t` rejects the `=` exact-match prefix other targets accept.
    public static func bootstrapCommand(tmuxPath: String, sessionName: String, sessionID: String?) -> String {
        let tmux = shellQuote(tmuxPath)
        let name = shellQuote(sessionName)
        let exact = shellQuote("=" + sessionName)
        var steps = [
            "unset TMUX TMUX_PANE",
            "\(tmux) setenv -g SSHIDO_SESSION 1 2>/dev/null || true",
        ]
        if let sessionID {
            let id = shellQuote(sessionID)
            steps.append(
                "if \(tmux) has-session -t \(id) 2>/dev/null; then "
                + "\(tmux) set -t \(id) mouse on 2>/dev/null || true; "
                + "exec \(tmux) attach -t \(id); fi"
            )
        }
        steps.append(
            "\(tmux) has-session -t \(exact) 2>/dev/null || "
            + "\(tmux) new-session -d -s \(name) -e SSHIDO_SESSION=1"
        )
        steps.append("\(tmux) set -t \(name) mouse on 2>/dev/null || true")
        steps.append("exec \(tmux) attach -t \(exact)")
        return "if command -v \(tmux) >/dev/null 2>&1; then \(steps.joined(separator: "; ")); fi"
    }

    public static func prepareCommand(tmuxPath: String, sessionName: String, sessionID: String?) -> String {
        let tmux = shellQuote(tmuxPath)
        let name = shellQuote(sessionName)
        let exact = shellQuote("=" + sessionName)
        var steps = [
            "export SSHIDO_SESSION=1",
            "command -v \(tmux) >/dev/null 2>&1 || { \(announce("")); exit 0; }",
            "\(tmux) setenv -g SSHIDO_SESSION 1 2>/dev/null || true",
        ]
        if let sessionID {
            let id = shellQuote(sessionID)
            steps.append(
                "if \(tmux) has-session -t \(id) 2>/dev/null; then "
                + "\(tmux) set -t \(id) mouse on 2>/dev/null || true; "
                + "\(announce(sessionID)); exit 0; fi"
            )
        }
        steps.append(
            "\(tmux) has-session -t \(exact) 2>/dev/null || "
            + "\(tmux) new-session -d -s \(name) -e SSHIDO_SESSION=1"
        )
        steps.append("\(tmux) set -t \(name) mouse on 2>/dev/null || true")
        steps.append(announce("=" + sessionName))
        return steps.joined(separator: "; ")
    }

    private static func announce(_ target: String) -> String {
        "printf '%s%s\\n' \(shellQuote(attachMarker)) \(shellQuote(target))"
    }

    public static func attachCommand(tmuxPath: String, target: String) -> String {
        "unset TMUX TMUX_PANE; exec \(shellQuote(tmuxPath)) attach -t \(shellQuote(target))"
    }

    public static func parseAttachTarget(_ output: String) -> TmuxAttachTarget? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            guard let marker = line.range(of: attachMarker) else { continue }
            let target = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            return target.isEmpty ? .noTmux : .attach(target)
        }
        return nil
    }

    public static func renameCommand(tmuxPath: String, target: String, newName: String) -> String {
        let tmux = shellQuote(tmuxPath)
        let t = shellQuote(target)
        return "\(tmux) rename-session -t \(t) \(shellQuote(newName)) 2>&1 && "
            + "{ printf %s \(shellQuote(renameMarker)); \(tmux) display-message -p -t \(t) '#{session_name}'; }; true"
    }

    public static func parseRenameResult(_ output: String) -> TmuxRenameResult {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let marker = line.range(of: renameMarker) else { continue }
            let name = String(line[marker.upperBound...])
            if !name.isEmpty { return .renamed(name) }
        }
        let reason = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return .failed(reason ?? "tmux did not report a result")
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func parse(_ output: String) -> [RemoteTmuxSession] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5,
                  parts[0].hasPrefix("$"),
                  let created = TimeInterval(parts[1]),
                  let windows = Int(parts[2]),
                  let attachedClients = Int(parts[3]),
                  !parts[4].isEmpty
            else { return nil }
            return RemoteTmuxSession(
                sessionID: String(parts[0]),
                name: String(parts[4]),
                windows: windows,
                createdAt: Date(timeIntervalSince1970: created),
                attached: attachedClients > 0
            )
        }
    }
}
