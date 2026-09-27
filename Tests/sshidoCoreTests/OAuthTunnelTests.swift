import XCTest
import Network
@testable import sshidoCore

// Node's `listen(port, "localhost")` binds ::1 only on macOS (wrangler login does this),
// so the forward must name "localhost" and let sshd try every address.
final class OAuthTunnelTests: XCTestCase {
    func testDefaultForwardTargetIsLocalhost() async throws {
        let port = 38976
        let channel = RecordingSSHChannel()
        let tunnel = OAuthTunnel(port: port, sshChannel: channel)
        try await tunnel.start()

        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        conn.start(queue: .global())
        conn.send(content: Data("GET / HTTP/1.1\r\n\r\n".utf8), completion: .idempotent)

        let deadline = Date().addingTimeInterval(5)
        while channel.targets.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        conn.cancel()
        await tunnel.stop()
        XCTAssertEqual(channel.targets, [RecordingSSHChannel.Target(host: "localhost", port: port)])
    }
}

private final class RecordingSSHChannel: SSHChannel, @unchecked Sendable {
    struct Target: Equatable {
        let host: String
        let port: Int
    }

    private let lock = NSLock()
    private var recorded: [Target] = []

    var targets: [Target] { lock.withLock { recorded } }

    func connect() async throws {}
    func disconnect() async {}
    func send(_ bytes: [UInt8]) async throws {}
    func enqueueInput(_ bytes: [UInt8]) {}
    func resize(cols: Int, rows: Int) async throws {}
    func setOutputHandler(onData: @escaping @Sendable (Data) async -> Void,
                          onClose: @escaping @Sendable () -> Void) {}
    var isConnected: Bool { get async { true } }

    func openForwardedChannel(host: String, port: Int) async throws -> SSHForwardedChannel {
        lock.withLock { recorded.append(Target(host: host, port: port)) }
        return ClosedForwardedChannel()
    }
}

private final class ClosedForwardedChannel: SSHForwardedChannel, @unchecked Sendable {
    let inbound = AsyncStream<Data> { $0.finish() }
    func send(_ data: Data) async throws {}
    func close() async {}
}
