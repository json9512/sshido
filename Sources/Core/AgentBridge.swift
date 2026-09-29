import Foundation
import Citadel
import NIOCore
#if canImport(sshidoModels)
import sshidoModels
#endif

@available(macOS 15.0, *)
public actor AgentBridge {
    private let channel: MetricsOnlySSHChannel
    private var writer: TTYStdinWriter?
    private var connected = false

    public init(channel: MetricsOnlySSHChannel) {
        self.channel = channel
    }

    private func ensureConnected() async throws {
        if connected { return }
        try await channel.connect()
        connected = true
    }

    public func run(_ command: String) async throws -> String {
        String(decoding: try await runData(command), as: UTF8.self)
    }

    public func runData(_ command: String) async throws -> Data {
        try await ensureConnected()
        return try await channel.executeCommand(command)
    }

    public func events(podman: String, since: Int64) -> AsyncThrowingStream<AgentLineDecoder.Output, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(podman: podman, since: since, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        podman: String,
        since: Int64,
        into continuation: AsyncThrowingStream<AgentLineDecoder.Output, Error>.Continuation
    ) async throws {
        try await ensureConnected()
        try await channel.withExec(AgentHostCommands.attach(podman: podman)) { inbound, outbound in
            self.setWriter(outbound)
            try await Self.write(.hello(since: since), to: outbound)
            var decoder = AgentLineDecoder()
            for try await output in inbound {
                guard case .stdout(let buffer) = output else { continue }
                let (next, lines) = decoder.feeding(Data(buffer: buffer))
                decoder = next
                lines.forEach { continuation.yield($0) }
            }
        }
        setWriter(nil)
    }

    private func setWriter(_ writer: TTYStdinWriter?) {
        self.writer = writer
    }

    public func send(_ request: AgentRequest) async throws {
        guard let writer else { throw SSHError.notConnected }
        try await Self.write(request, to: writer)
    }

    private static func write(_ request: AgentRequest, to writer: TTYStdinWriter) async throws {
        try await writer.write(ByteBuffer(data: try AgentLineDecoder.encode(request)))
    }

    public func disconnect() async {
        setWriter(nil)
        connected = false
        await channel.disconnect()
    }
}
