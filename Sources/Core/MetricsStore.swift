import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public enum MetricsSettings {
    public static let intervalKey = "sshido.metrics.intervalSeconds"
    public static let defaultIntervalSeconds = 2
    public static let allowedIntervals: [Int] = [1, 2, 5]
}

public enum MetricsEvent: Sendable {
    case sample(ServerMetricsSample)
    case error(String)
}

public actor MetricsStore {
    public static let shared = MetricsStore()

    private struct Subscription {
        let id: UUID
        let continuation: AsyncStream<MetricsEvent>.Continuation
    }

    private struct Pump {
        let collector: ServerMetricsCollector
        var subscribers: [Subscription]
        var task: Task<Void, Never>
        let interval: Duration
        var lastSample: ServerMetricsSample?
        var lastError: String?
    }

    private var pumps: [UUID: Pump] = [:]

    public init() {}

    public func samples(
        sessionID: UUID,
        channelProvider: @escaping @Sendable () async -> SSHChannel?,
        interval: Duration = .seconds(2)
    ) -> AsyncStream<MetricsEvent> {
        let (stream, continuation) = AsyncStream<MetricsEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(2)
        )
        let subID = UUID()
        attach(
            sessionID: sessionID,
            channelProvider: channelProvider,
            interval: interval,
            subscription: Subscription(id: subID, continuation: continuation)
        )
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.detach(sessionID: sessionID, subID: subID) }
        }
        return stream
    }

    public func stop(sessionID: UUID) {
        guard let pump = pumps.removeValue(forKey: sessionID) else { return }
        pump.task.cancel()
        for sub in pump.subscribers { sub.continuation.finish() }
    }

    private func attach(
        sessionID: UUID,
        channelProvider: @escaping @Sendable () async -> SSHChannel?,
        interval: Duration,
        subscription: Subscription
    ) {
        if var existing = pumps[sessionID] {
            if let last = existing.lastSample {
                subscription.continuation.yield(.sample(last))
            }
            if let err = existing.lastError {
                subscription.continuation.yield(.error(err))
            }
            existing.subscribers.append(subscription)
            pumps[sessionID] = existing
            return
        }
        let collector = ServerMetricsCollector(channelProvider: channelProvider)
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.run(sessionID: sessionID, collector: collector, interval: interval)
        }
        pumps[sessionID] = Pump(
            collector: collector,
            subscribers: [subscription],
            task: task,
            interval: interval,
            lastSample: nil,
            lastError: nil
        )
        NSLog("[sshido] metrics pump START sid=\(sessionID.uuidString.prefix(8)) interval=\(interval)")
    }

    private func detach(sessionID: UUID, subID: UUID) {
        guard var pump = pumps[sessionID] else { return }
        pump.subscribers.removeAll { $0.id == subID }
        if pump.subscribers.isEmpty {
            pump.task.cancel()
            pumps.removeValue(forKey: sessionID)
            NSLog("[sshido] metrics pump STOP sid=\(sessionID.uuidString.prefix(8)) (last subscriber gone)")
        } else {
            pumps[sessionID] = pump
        }
    }

    private func run(sessionID: UUID, collector: ServerMetricsCollector, interval: Duration) async {
        NSLog("[sshido] metrics pump LOOP enter sid=\(sessionID.uuidString.prefix(8))")
        while !Task.isCancelled {
            let started = Date()
            do {
                let sample = try await collector.sample()
                let elapsed = Date().timeIntervalSince(started)
                NSLog("[sshido] metrics sample OK sid=\(sessionID.uuidString.prefix(8)) os=\(sample.host.os.rawValue) elapsed=\(String(format: "%.2f", elapsed))s cpu=\(sample.cpu?.totalPercent ?? -1) memUsed=\(sample.memory?.usedBytes ?? 0)")
                emit(sessionID: sessionID, event: .sample(sample))
            } catch {
                let msg = String(describing: error)
                NSLog("[sshido] metrics sample ERR sid=\(sessionID.uuidString.prefix(8)) error=\(msg)")
                emit(sessionID: sessionID, event: .error(msg))
            }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
        NSLog("[sshido] metrics pump LOOP exit sid=\(sessionID.uuidString.prefix(8))")
    }

    private func emit(sessionID: UUID, event: MetricsEvent) {
        guard var pump = pumps[sessionID] else { return }
        switch event {
        case .sample(let s):
            pump.lastSample = s
            pump.lastError = nil
        case .error(let e):
            pump.lastError = e
        }
        pumps[sessionID] = pump
        for sub in pump.subscribers { sub.continuation.yield(event) }
    }
}
