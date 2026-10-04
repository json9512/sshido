import Foundation
import NIOPosix
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
    func executeCommand(_ command: String) async throws -> Data
    func setOutputHandler(onData: @escaping @Sendable (Data) async -> Void,
                          onClose: @escaping @Sendable () -> Void)
    var isConnected: Bool { get async }
    var isClosed: Bool { get async }
    var connectFailure: SSHError? { get async }
}

public extension SSHChannel {
    func uploadFile(data: Data, remotePath: String) async throws {
        throw SSHError.transport("uploadFile not supported on this channel")
    }

    func openForwardedChannel(host: String, port: Int) async throws -> SSHForwardedChannel {
        throw SSHError.transport("port forwarding not supported on this channel")
    }

    func executeCommand(_ command: String) async throws -> Data {
        throw SSHError.transport("executeCommand not supported on this channel")
    }

    func enqueueInput(_ bytes: [UInt8]) {
        Task { try? await self.send(bytes) }
    }

    var connectFailure: SSHError? { get async { nil } }
}

public struct ShellBootstrap: Sendable {
    public let prepare: String?
    public let typed: @Sendable (String?) -> String?

    public init(prepare: String?, typed: @escaping @Sendable (String?) -> String?) {
        self.prepare = prepare
        self.typed = typed
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
    case hostNotFound(host: String, port: Int)

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
        case .hostNotFound(let h, _):
            return "Can't find \(h). If it's a Tailscale or VPN address, open Tailscale (or your VPN app) on this device and check it's connected and signed in."
        }
    }

    static func hostLookupFailure(_ error: Error) -> SSHError? {
        guard let e = error as? NIOConnectionError, e.dnsAError != nil || e.dnsAAAAError != nil else { return nil }
        return .hostNotFound(host: e.host, port: e.port)
    }
}
