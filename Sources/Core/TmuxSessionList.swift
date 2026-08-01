import Foundation

public struct RemoteTmuxSession: Hashable, Sendable, Identifiable {
    public let name: String
    public let windows: Int
    public let createdAt: Date
    public let attached: Bool
    public var id: String { name }

    public init(name: String, windows: Int, createdAt: Date, attached: Bool) {
        self.name = name
        self.windows = windows
        self.createdAt = createdAt
        self.attached = attached
    }
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

    // Login shell first so tmux resolves on the PATH the interactive session uses;
    // the probe covers shells that reject `-lc`. Trailing `true` keeps exit status 0 —
    // Citadel throws CommandFailed otherwise.
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

    public static func listCommand(tmuxPath: String) -> String {
        let quoted = shellQuote(tmuxPath)
        return "\(quoted) ls -F '#{session_created}:#{session_windows}:#{session_attached}:#{session_name}' 2>/dev/null; true"
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func parse(_ output: String) -> [RemoteTmuxSession] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4,
                  let created = TimeInterval(parts[0]),
                  let windows = Int(parts[1]),
                  let attachedClients = Int(parts[2]),
                  !parts[3].isEmpty
            else { return nil }
            return RemoteTmuxSession(
                name: String(parts[3]),
                windows: windows,
                createdAt: Date(timeIntervalSince1970: created),
                attached: attachedClients > 0
            )
        }
    }
}
