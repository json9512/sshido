import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

extension Session {
    /// Sessions stored before tmux names were recorded fall back to the name their
    /// bootstrap derives from the session id.
    public func displayName(on host: RemoteHost) -> String {
        if let tmuxName, !tmuxName.isEmpty { return tmuxName }
        guard host.useTmux else { return title }
        return TmuxSessionList.sessionName(prefix: host.tmuxSession, sessionID: id)
    }
}
