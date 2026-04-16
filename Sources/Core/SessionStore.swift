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
            bootstrap = "unset TMUX TMUX_PANE; exec /opt/homebrew/bin/tmux new -A -s \(name)"
        } else {
            bootstrap = nil
        }
        var env: [String: String] = ["TERM": "xterm-256color"]
        if host.forceCompactAgent {
            env["NO_COLOR"] = "1"
        }
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
