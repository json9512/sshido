import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public protocol SSHChannel: AnyObject, Sendable {
    func connect() async throws
    func disconnect() async
    func send(_ bytes: [UInt8]) async throws
    func enqueueInput(_ bytes: [UInt8])
    func resize(cols: Int, rows: Int) async throws
    func uploadFile(data: Data, remotePath: String) async throws
    func openForwardedChannel(host: String, port: Int) async throws -> SSHForwardedChannel
    var output: AsyncStream<Data> { get }
    var isConnected: Bool { get async }
}

public extension SSHChannel {
    func uploadFile(data: Data, remotePath: String) async throws {
        throw SSHError.transport("uploadFile not supported on this channel")
    }

    func openForwardedChannel(host: String, port: Int) async throws -> SSHForwardedChannel {
        throw SSHError.transport("port forwarding not supported on this channel")
    }

    func enqueueInput(_ bytes: [UInt8]) {
        Task { try? await self.send(bytes) }
    }
}

public protocol SSHForwardedChannel: AnyObject, Sendable {
    var inbound: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
}

public enum SSHError: Error, CustomStringConvertible, Sendable {
    case notConnected
    case authFailed(String)
    case transport(String)
    case invalidKey(String)
    case hostKeyChanged(host: String, port: Int, expected: String, presented: String)
    case hostKeyRejected(host: String, port: Int)

    public var description: String {
        switch self {
        case .notConnected:        return "not connected"
        case .authFailed(let m):   return "authentication failed: \(m)"
        case .transport(let m):    return "transport error: \(m)"
        case .invalidKey(let m):   return "invalid key: \(m)"
        case .hostKeyChanged(let h, let p, _, _):
            return "host key for \(h):\(p) has changed — connection blocked"
        case .hostKeyRejected(let h, let p):
            return "host key for \(h):\(p) was not trusted — connection cancelled"
        }
    }
}
