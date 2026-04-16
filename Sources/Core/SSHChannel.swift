import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public protocol SSHChannel: AnyObject, Sendable {
    func connect() async throws
    func disconnect() async
    func send(_ bytes: [UInt8]) async throws
    func resize(cols: Int, rows: Int) async throws
    func uploadFile(data: Data, remotePath: String) async throws
    var output: AsyncStream<Data> { get }
    var isConnected: Bool { get async }
}

public extension SSHChannel {
    func uploadFile(data: Data, remotePath: String) async throws {
        throw SSHError.transport("uploadFile not supported on this channel")
    }
}

public enum SSHError: Error, CustomStringConvertible, Sendable {
    case notConnected
    case authFailed(String)
    case transport(String)
    case invalidKey(String)

    public var description: String {
        switch self {
        case .notConnected:        return "not connected"
        case .authFailed(let m):   return "authentication failed: \(m)"
        case .transport(let m):    return "transport error: \(m)"
        case .invalidKey(let m):   return "invalid key: \(m)"
        }
    }
}
