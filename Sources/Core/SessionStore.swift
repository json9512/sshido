import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor SessionStore {
    public static let shared = SessionStore()

    private let url: URL
    private var sessions: [UUID: Session] = [:]
    private var channels: [UUID: SSHChannel] = [:]

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
        let session = Session(
            hostID: host.id,
            title: title ?? "Session \(count)"
        )
        sessions[session.id] = session
        try? persist()
        channels[session.id] = makeChannel(for: host, auth: auth, sessionID: session.id)
        return session
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

    public func renameSession(id: UUID, title: String) {
        guard var s = sessions[id], s.title != title else { return }
        s.title = title
        sessions[id] = s
        try? persist()
    }

    public func close(sessionID: UUID) async {
        if let ch = channels.removeValue(forKey: sessionID) {
            await ch.disconnect()
        }
        sessions.removeValue(forKey: sessionID)
        try? persist()
    }

    public func closeAll(for hostID: UUID) async {
        for s in sessions(for: hostID) {
            await close(sessionID: s.id)
        }
    }

    private func makeChannel(for host: RemoteHost, auth: SSHAuth, sessionID: UUID) -> SSHChannel {
        let bootstrap: String?
        if host.useTmux {
            let name = shellEscape(tmuxName(host: host, session: sessionID))
            bootstrap = "if command -v tmux >/dev/null 2>&1; then unset TMUX TMUX_PANE; exec tmux new -A -s \(name); fi"
        } else {
            bootstrap = nil
        }
        let env: [String: String] = ["TERM": "xterm-256color"]
        return CitadelSSHChannel(
            host: host.hostname,
            port: host.port,
            user: host.username,
            auth: auth,
            bootstrapCommand: bootstrap,
            environment: env
        )
    }

    private func tmuxName(host: RemoteHost, session: UUID) -> String {
        let prefix = host.tmuxSession.isEmpty ? "sshido" : host.tmuxSession
        let short = String(session.uuidString.prefix(8))
        return "\(prefix)-\(short)"
    }

    private nonisolated func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func persist() throws {
        let arr = Array(sessions.values).sorted { $0.createdAt < $1.createdAt }
        let data = try JSONEncoder().encode(arr)
        try data.write(to: url, options: .atomic)
    }
}
