import Foundation
import Citadel
import NIOCore
import NIOSSH

public final class CitadelForwardedChannel: SSHForwardedChannel, @unchecked Sendable {
    public let inbound: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let channel: Channel

    private init(channel: Channel,
                 inbound: AsyncStream<Data>,
                 continuation: AsyncStream<Data>.Continuation) {
        self.channel = channel
        self.inbound = inbound
        self.continuation = continuation
    }

    static func open(client: SSHClient, host: String, port: Int) async throws -> CitadelForwardedChannel {
        let (stream, continuation) = AsyncStream<Data>.makeStream(of: Data.self)
        let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let settings = SSHChannelType.DirectTCPIP(
            targetHost: host,
            targetPort: port,
            originatorAddress: originator
        )
        let nioChannel = try await client.createDirectTCPIPChannel(using: settings) { channel in
            let handler = InboundForwardingHandler(
                onData: { data in continuation.yield(data) },
                onClose: { continuation.finish() }
            )
            return channel.pipeline.addHandler(handler)
        }
        nioChannel.closeFuture.whenComplete { _ in continuation.finish() }
        return CitadelForwardedChannel(channel: nioChannel, inbound: stream, continuation: continuation)
    }

    public func send(_ data: Data) async throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer).get()
    }

    public func close() async {
        continuation.finish()
        guard channel.isActive else { return }
        try? await channel.close(mode: .all).get()
    }
}

private final class InboundForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let onData: @Sendable (Data) -> Void
    private let onClose: @Sendable () -> Void

    init(onData: @escaping @Sendable (Data) -> Void,
         onClose: @escaping @Sendable () -> Void) {
        self.onData = onData
        self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        onData(Data(buffer: buf))
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onClose()
        context.fireErrorCaught(error)
    }
}
