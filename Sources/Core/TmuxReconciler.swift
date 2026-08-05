import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public struct TmuxBinding: Equatable, Sendable {
    public let localID: UUID
    public let remote: RemoteTmuxSession

    public init(localID: UUID, remote: RemoteTmuxSession) {
        self.localID = localID
        self.remote = remote
    }
}

public enum TmuxReconciler {
    /// Pairs local sessions with what `tmux ls` reports; unmatched remotes come back for
    /// adoption. The id pass catches server-side renames, but only with the creation stamp
    /// agreeing — tmux reissues "$0" after a restart and the id alone would bind a stranger.
    public static func plan(
        locals: [Session],
        remotes: [RemoteTmuxSession],
        derivedName: (Session) -> String
    ) -> (bindings: [TmuxBinding], unknown: [RemoteTmuxSession]) {
        var byName: [String: RemoteTmuxSession] = [:]
        for r in remotes where byName[r.name] == nil { byName[r.name] = r }

        var bindings: [TmuxBinding] = []
        var claimed: Set<String> = []
        var matched: Set<UUID> = []

        for s in locals {
            guard let r = byName[s.tmuxName ?? derivedName(s)], !claimed.contains(r.sessionID) else { continue }
            claimed.insert(r.sessionID)
            matched.insert(s.id)
            bindings.append(TmuxBinding(localID: s.id, remote: r))
        }

        for s in locals where !matched.contains(s.id) {
            guard let sid = s.tmuxSessionID, let created = s.tmuxCreatedAt else { continue }
            guard let r = remotes.first(where: {
                $0.sessionID == sid
                    && !claimed.contains($0.sessionID)
                    && sameInstant($0.createdAt, created)
            }) else { continue }
            claimed.insert(r.sessionID)
            bindings.append(TmuxBinding(localID: s.id, remote: r))
        }

        return (bindings, remotes.filter { !claimed.contains($0.sessionID) })
    }

    private static func sameInstant(_ a: Date, _ b: Date) -> Bool {
        Int(a.timeIntervalSince1970) == Int(b.timeIntervalSince1970)
    }
}
