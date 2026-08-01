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
    // Runs through a login shell so tmux is found on the same PATH the interactive
    // session uses (Homebrew installs outside the bare exec-channel PATH). Trailing
    // `true` keeps the exit status 0 — Citadel throws CommandFailed on non-zero exit,
    // and `tmux ls` exits 1 when no server is running.
    public static let command =
        "${SHELL:-/bin/sh} -lc 'command -v tmux >/dev/null 2>&1 && tmux ls -F \"#{session_created}:#{session_windows}:#{session_attached}:#{session_name}\" 2>/dev/null'; true"

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
