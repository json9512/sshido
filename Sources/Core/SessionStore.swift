import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public enum TmuxRenameError: LocalizedError, Equatable {
    case emptyName
    case sessionGone
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Session name can't be empty."
        case .sessionGone: return "That session is no longer open."
        case .rejected(let reason): return reason
        }
    }
}

public actor SessionStore {
    public static let shared = SessionStore()

    private let url: URL
    private var sessions: [UUID: Session] = [:]
    private var channels: [UUID: SSHChannel] = [:]
    private var tmuxPaths: [UUID: String] = [:]

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("sessions.json")
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([Session].self, from: data) {
            for s in arr { sessions[s.id] = s }
        }
    }

    public func allSessions() -> [Session] {
        Array(sessions.values).sorted { $0.createdAt < $1.createdAt }
    }

    public func sessions(for hostID: UUID) -> [Session] {
        sessions.values
            .filter { $0.hostID == hostID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func openSession(for host: RemoteHost, auth: SSHAuth, title: String? = nil) -> Session {
        let count = sessions(for: host.id).count + 1
        let id = UUID()
        let tmux = host.useTmux ? tmuxName(host: host, session: id) : nil
        let session = Session(
            id: id,
            hostID: host.id,
            title: title ?? tmux ?? "Session \(count)",
            tmuxName: tmux
        )
        sessions[session.id] = session
        persistLogged()
        channels[session.id] = makeChannel(for: host, auth: auth, sessionID: session.id)
        return session
    }

    public func adoptRemoteSession(for host: RemoteHost, auth: SSHAuth, remote: RemoteTmuxSession) -> Session {
        let session = Session(
            hostID: host.id,
            title: remote.name,
            tmuxName: remote.name,
            tmuxSessionID: remote.sessionID,
            tmuxCreatedAt: remote.createdAt
        )
        sessions[session.id] = session
        persistLogged()
        channels[session.id] = makeChannel(for: host, auth: auth, sessionID: session.id)
        return session
    }

    /// Learns each session's tmux id, picks up renames made on the server, and returns
    /// the sessions this device isn't tracking.
    public func syncRemoteSessions(for host: RemoteHost, auth: SSHAuth) async throws -> [RemoteTmuxSession] {
        let raw = try await withExecChannel(for: host, auth: auth) { ch in
            guard let path = try await self.resolveTmuxPath(for: host.id, using: ch) else { return "" }
            let out = try await ch.executeCommand(TmuxSessionList.listCommand(tmuxPath: path))
            return String(decoding: out, as: UTF8.self)
        }
        return reconcile(remotes: TmuxSessionList.parse(raw), host: host)
    }

    private func reconcile(remotes: [RemoteTmuxSession], host: RemoteHost) -> [RemoteTmuxSession] {
        let plan = TmuxReconciler.plan(
            locals: sessions(for: host.id),
            remotes: remotes,
            derivedName: { self.tmuxName(host: host, session: $0.id) }
        )
        for binding in plan.bindings {
            guard var s = sessions[binding.localID] else { continue }
            if s.tmuxName != binding.remote.name {
                Log.session.info("tmux session now named \(binding.remote.name, privacy: .public)")
            }
            s.tmuxName = binding.remote.name
            s.title = binding.remote.name
            s.tmuxSessionID = binding.remote.sessionID
            s.tmuxCreatedAt = binding.remote.createdAt
            sessions[binding.localID] = s
        }
        // Unbound means gone from the server; dropping the id keeps a recycled "$0"
        // from later pointing at a session that isn't ours.
        let bound = Set(plan.bindings.map(\.localID))
        for s in sessions(for: host.id) where !bound.contains(s.id) && s.tmuxSessionID != nil {
            var stale = s
            stale.tmuxSessionID = nil
            stale.tmuxCreatedAt = nil
            sessions[s.id] = stale
        }
        persistLogged()
        return plan.unknown
    }

    /// `nil` when the session is not on the host. Acting on a stale id either does nothing
    /// (`kill-session` exits quietly) or hits whichever session inherited the id.
    private func refreshedTarget(
        for sessionID: UUID,
        host: RemoteHost,
        path: String,
        channel: SSHChannel
    ) async throws -> String? {
        let out = try await channel.executeCommand(TmuxSessionList.listCommand(tmuxPath: path))
        _ = reconcile(remotes: TmuxSessionList.parse(String(decoding: out, as: UTF8.self)), host: host)
        return sessions[sessionID]?.tmuxSessionID
    }

    /// Fails open — anything unexpected keeps today's behaviour rather than eating a scroll.
    public func paneForwardsWheel(for session: Session, host: RemoteHost, auth: SSHAuth) async -> Bool {
        guard host.useTmux else { return true }
        let current = sessions[session.id] ?? session
        let target = current.tmuxSessionID
            ?? current.tmuxName
            ?? tmuxName(host: host, session: session.id)
        do {
            return try await withExecChannel(for: host, auth: auth) { ch in
                guard let path = try await self.resolveTmuxPath(for: host.id, using: ch) else { return true }
                let out = try await ch.executeCommand(
                    TmuxPaneMouse.stateCommand(tmuxPath: path, target: target)
                )
                guard let state = TmuxPaneMouse.parse(String(decoding: out, as: UTF8.self)) else { return true }
                return TmuxPaneMouse.forwardsWheel(state)
            }
        } catch {
            Log.session.error("pane mouse probe failed: \(String(describing: error), privacy: .public)")
            return true
        }
    }

    @discardableResult
    public func renameSession(
        _ session: Session,
        host: RemoteHost,
        auth: SSHAuth,
        to newName: String
    ) async throws -> Session {
        let wanted = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { throw TmuxRenameError.emptyName }
        guard host.useTmux else { return try applyRename(session.id, to: wanted, tmux: false) }

        let output = try await withExecChannel(for: host, auth: auth) { ch -> String? in
            guard let path = try await self.resolveTmuxPath(for: host.id, using: ch),
                  let target = try await self.refreshedTarget(
                      for: session.id, host: host, path: path, channel: ch
                  )
            else { return nil }
            let out = try await ch.executeCommand(
                TmuxSessionList.renameCommand(tmuxPath: path, target: target, newName: wanted)
            )
            return String(decoding: out, as: UTF8.self)
        }
        // Nothing to rename on the host, so the next connect creates it under this name.
        guard let output else { return try applyRename(session.id, to: wanted, tmux: true) }

        switch TmuxSessionList.parseRenameResult(output) {
        case .renamed(let actual):
            return try applyRename(session.id, to: actual, tmux: true)
        case .failed(let reason):
            Log.session.error("tmux rename failed: \(reason, privacy: .public)")
            throw TmuxRenameError.rejected(reason)
        }
    }

    private func applyRename(_ id: UUID, to name: String, tmux: Bool) throws -> Session {
        guard var s = sessions[id] else { throw TmuxRenameError.sessionGone }
        s.title = name
        if tmux { s.tmuxName = name }
        sessions[id] = s
        persistLogged()
        return s
    }

    public func killRemoteSession(_ session: Session, host: RemoteHost, auth: SSHAuth) async throws {
        try await withExecChannel(for: host, auth: auth) { ch in
            guard let path = try await self.resolveTmuxPath(for: host.id, using: ch),
                  let target = try await self.refreshedTarget(
                      for: session.id, host: host, path: path, channel: ch
                  )
            else { return }
            _ = try await ch.executeCommand(TmuxSessionList.killCommand(tmuxPath: path, target: target))
        }
        await close(sessionID: session.id)
    }

    private func resolveTmuxPath(for hostID: UUID, using channel: SSHChannel) async throws -> String? {
        if let cached = tmuxPaths[hostID] { return cached }
        let out = try await channel.executeCommand(TmuxSessionList.resolveCommand)
        guard let path = TmuxSessionList.parseResolvedPath(String(decoding: out, as: UTF8.self)) else {
            Log.session.info("tmux not found on host \(hostID.uuidString.prefix(8), privacy: .public)")
            return nil
        }
        tmuxPaths[hostID] = path
        Log.session.info("resolved tmux at \(path, privacy: .public)")
        return path
    }

    private func withExecChannel<T>(
        for host: RemoteHost,
        auth: SSHAuth,
        _ body: (SSHChannel) async throws -> T
    ) async throws -> T {
        if let ch = await connectedChannel(for: host.id) {
            return try await body(ch)
        }
        let ch = metricsChannel(for: host, auth: auth)
        try await ch.connect()
        do {
            let result = try await body(ch)
            await ch.disconnect()
            return result
        } catch {
            await ch.disconnect()
            throw error
        }
    }

    private func connectedChannel(for hostID: UUID) async -> SSHChannel? {
        for s in sessions(for: hostID) {
            if let ch = channels[s.id], await ch.isConnected {
                return ch
            }
        }
        return nil
    }

    public func channel(for sessionID: UUID) -> SSHChannel? {
        channels[sessionID]
    }

    public func connectedSessionIDs(for hostID: UUID) async -> Set<UUID> {
        var out: Set<UUID> = []
        for s in sessions(for: hostID) {
            if let ch = channels[s.id], await ch.isConnected {
                out.insert(s.id)
            }
        }
        return out
    }

    public func connectedHostIDs() async -> Set<UUID> {
        let channelSnapshot = channels
        let sessionSnapshot = sessions
        var out: Set<UUID> = []
        for (sid, ch) in channelSnapshot {
            if await ch.isConnected, let s = sessionSnapshot[sid] {
                out.insert(s.hostID)
            }
        }
        return out
    }

    public func ensureChannel(for session: Session, host: RemoteHost, auth: SSHAuth) async -> SSHChannel {
        if let existing = channels[session.id], await existing.isConnected {
            return existing
        }
        if let dead = channels.removeValue(forKey: session.id) {
            await dead.disconnect()
        }
        let ch = makeChannel(for: host, auth: auth, sessionID: session.id)
        channels[session.id] = ch
        return ch
    }

    public func session(_ id: UUID) -> Session? {
        sessions[id]
    }

    public func close(sessionID: UUID) async {
        await MetricsStore.shared.stop(sessionID: sessionID)
        if let ch = channels.removeValue(forKey: sessionID) {
            await ch.disconnect()
        }
        sessions.removeValue(forKey: sessionID)
        persistLogged()
    }

    public func closeAll(for hostID: UUID) async {
        for s in sessions(for: hostID) {
            await close(sessionID: s.id)
        }
    }

    private func makeChannel(for host: RemoteHost, auth: SSHAuth, sessionID: UUID) -> SSHChannel {
        let bootstrap: String?
        if host.useTmux {
            let session = sessions[sessionID]
            bootstrap = TmuxSessionList.bootstrapCommand(
                tmuxPath: tmuxPaths[host.id] ?? "tmux",
                sessionName: session?.tmuxName ?? tmuxName(host: host, session: sessionID),
                sessionID: session?.tmuxSessionID
            )
        } else {
            bootstrap = nil
        }
        let env: [String: String] = ["SSHIDO_SESSION": "1"]
        return CitadelSSHChannel(
            host: host.hostname,
            port: host.port,
            user: host.username,
            auth: auth,
            bootstrapCommand: bootstrap,
            environment: env,
            hostKeyConfirm: hostKeyConfirm
        )
    }

    // Injected at app startup so sshidoCore doesn't depend on sshidoUI.
    // Default rejects everything — anyone forgetting to wire it up fails closed.
    private var hostKeyConfirm: HostKeyConfirmCallback = { _ in .reject }

    public func setHostKeyConfirm(_ confirm: @escaping HostKeyConfirmCallback) {
        self.hostKeyConfirm = confirm
    }

    public func metricsChannel(for host: RemoteHost, auth: SSHAuth) -> MetricsOnlySSHChannel {
        MetricsOnlySSHChannel(
            host: host.hostname,
            port: host.port,
            user: host.username,
            auth: auth,
            hostKeyConfirm: hostKeyConfirm
        )
    }

    private func tmuxName(host: RemoteHost, session: UUID) -> String {
        TmuxSessionList.sessionName(prefix: host.tmuxSession, sessionID: session)
    }

    private func persist() throws {
        let arr = Array(sessions.values).sorted { $0.createdAt < $1.createdAt }
        let data = try JSONEncoder().encode(arr)
        try data.write(to: url, options: .atomic)
    }

    private func persistLogged() {
        do {
            try persist()
        } catch {
            Log.store.error("SessionStore persist failed: \(String(describing: error), privacy: .public)")
        }
    }
}
