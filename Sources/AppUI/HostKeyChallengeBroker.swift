#if canImport(UIKit)
import Foundation
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

/// Bridges the NIO-event-loop host-key callback to a SwiftUI modal sheet.
///
/// Flow:
/// 1. `CitadelSSHChannel` is constructed with a callback that calls
///    `broker.awaitDecision(for:)`.
/// 2. The callback is invoked on a Task off the NIO event loop; it
///    publishes `pending` and parks the continuation.
/// 3. The root view's `.sheet(item: $broker.pending)` opens the modal.
/// 4. User taps Trust or Cancel; modal calls `broker.resolve(decision)`,
///    which resumes the continuation and clears `pending`.
/// 5. The original `await` returns; the SSH stack completes the
///    validation promise; the connection proceeds or fails.
@MainActor
public final class HostKeyChallengeBroker: ObservableObject {
    public static let shared = HostKeyChallengeBroker()

    @Published public var pending: HostKeyChallenge?
    private var continuation: CheckedContinuation<HostKeyDecision, Never>?

    public init() {}

    public func awaitDecision(for challenge: HostKeyChallenge) async -> HostKeyDecision {
        await withCheckedContinuation { cont in
            if continuation != nil {
                // A previous prompt is still mid-flight — reject the new one
                // rather than dropping the old continuation on the floor. In
                // practice this only happens if the user kicks off two
                // connections to different first-seen hosts at the same time.
                cont.resume(returning: .reject)
                return
            }
            continuation = cont
            pending = challenge
        }
    }

    public func resolve(_ decision: HostKeyDecision) {
        let cont = continuation
        continuation = nil
        pending = nil
        cont?.resume(returning: decision)
    }

    /// Adapter callback for code that wants to inject the broker into
    /// `CitadelSSHChannel`'s `hostKeyConfirm` parameter without importing
    /// the broker directly.
    public nonisolated func makeCallback() -> HostKeyConfirmCallback {
        { @Sendable challenge in
            await self.awaitDecision(for: challenge)
        }
    }
}
#endif
