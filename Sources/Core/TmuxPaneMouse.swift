import Foundation

public struct PaneMouseState: Equatable, Sendable {
    public let appWantsMouse: Bool
    public let command: String

    public init(appWantsMouse: Bool, command: String) {
        self.appWantsMouse = appWantsMouse
        self.command = command
    }
}

public enum TmuxPaneMouse {
    // `-t` here takes a session id or a bare name; the `=` exact-match prefix yields nothing.
    public static func stateCommand(tmuxPath: String, target: String) -> String {
        "\(TmuxSessionList.shellQuote(tmuxPath)) display-message -p -t "
            + "\(TmuxSessionList.shellQuote(target)) '#{mouse_any_flag}:#{pane_current_command}' "
            + "2>/dev/null; true"
    }

    public static func parse(_ output: String) -> PaneMouseState? {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "0" || parts[0] == "1" else { continue }
            let command = parts[1].trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { continue }
            return PaneMouseState(appWantsMouse: parts[0] == "1", command: command)
        }
        return nil
    }

    /// A pane still flagged for mouse reporting while a shell sits in it is a TUI that exited
    /// without clearing the flag. tmux forwards wheel bytes there and the shell echoes them as
    /// text, so those are the only events worth withholding — everything else scrolls as before.
    public static func forwardsWheel(_ state: PaneMouseState) -> Bool {
        guard state.appWantsMouse else { return true }
        return !isShell(state.command)
    }

    static func isShell(_ command: String) -> Bool {
        var name = Substring(command)
        if name.hasPrefix("-") { name = name.dropFirst() }
        if let slash = name.lastIndex(of: "/") { name = name[name.index(after: slash)...] }
        return shellNames.contains(String(name).lowercased())
    }

    private static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "mksh", "ash", "csh", "tcsh", "busybox",
    ]
}
