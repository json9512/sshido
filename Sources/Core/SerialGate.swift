import Foundation

public actor SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        guard !waiters.isEmpty else {
            busy = false
            return
        }
        waiters.removeFirst().resume()
    }
}
