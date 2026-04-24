import Foundation
import Network

public actor OAuthTunnel {
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case stopped
    }

    private let port: Int
    private let sshChannel: SSHChannel
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var state: State = .idle
    private var connections: [NWConnection] = []
    private var forwarded: [SSHForwardedChannel] = []
    private var pumpTasks: [Task<Void, Never>] = []

    public init(port: Int, sshChannel: SSHChannel) {
        self.port = port
        self.sshChannel = sshChannel
        self.queue = DispatchQueue(label: "app.sshido.oauth-tunnel.\(port)")
    }

    public var currentState: State { state }

    public func start() throws {
        guard state == .idle else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SSHError.transport("invalid tunnel port \(port)")
        }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            throw SSHError.transport("bind 127.0.0.1:\(port) failed: \(error)")
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { conn.cancel(); return }
            Task { await self.accept(conn) }
        }
        listener.start(queue: queue)
        self.listener = listener
        self.state = .listening
    }

    public func stop() async {
        guard state != .stopped else { return }
        state = .stopped
        listener?.cancel()
        listener = nil
        for task in pumpTasks { task.cancel() }
        pumpTasks.removeAll()
        for c in connections { c.cancel() }
        connections.removeAll()
        let toClose = forwarded
        forwarded.removeAll()
        for f in toClose { await f.close() }
    }

    private func accept(_ conn: NWConnection) async {
        guard state == .listening else { conn.cancel(); return }
        let fwd: SSHForwardedChannel
        do {
            fwd = try await sshChannel.openForwardedChannel(host: "127.0.0.1", port: port)
        } catch {
            conn.cancel()
            return
        }
        connections.append(conn)
        forwarded.append(fwd)
        conn.start(queue: queue)

        let uploadTask = Task {
            await Self.pumpConnectionToForwarded(conn: conn, fwd: fwd)
            await self.closeConnection(conn, fwd: fwd)
        }
        let downloadTask = Task {
            await Self.pumpForwardedToConnection(fwd: fwd, conn: conn)
            await self.closeConnection(conn, fwd: fwd)
        }
        pumpTasks.append(uploadTask)
        pumpTasks.append(downloadTask)
    }

    private var closedConnections: Set<ObjectIdentifier> = []

    private func closeConnection(_ conn: NWConnection, fwd: SSHForwardedChannel) async {
        let id = ObjectIdentifier(conn)
        guard !closedConnections.contains(id) else { return }
        closedConnections.insert(id)
        conn.cancel()
        await fwd.close()
        if let idx = connections.firstIndex(where: { $0 === conn }) {
            connections.remove(at: idx)
        }
        if let idx = forwarded.firstIndex(where: { $0 === fwd }) {
            forwarded.remove(at: idx)
        }
    }

    private static func pumpConnectionToForwarded(conn: NWConnection, fwd: SSHForwardedChannel) async {
        while !Task.isCancelled {
            let chunk: Data?
            do {
                chunk = try await receive(conn)
            } catch {
                return
            }
            guard let chunk, !chunk.isEmpty else { return }
            do {
                try await fwd.send(chunk)
            } catch {
                return
            }
        }
    }

    private static func pumpForwardedToConnection(fwd: SSHForwardedChannel, conn: NWConnection) async {
        for await chunk in fwd.inbound {
            if Task.isCancelled { return }
            await send(chunk, on: conn)
        }
    }

    private static func receive(_ conn: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                    return
                }
                cont.resume(returning: isComplete ? nil : Data())
            }
        }
    }

    private static func send(_ data: Data, on conn: NWConnection) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            conn.send(content: data, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}
