#if canImport(UIKit)
import Foundation
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
public final class HostKeyChallengeBroker: ObservableObject {
    public static let shared = HostKeyChallengeBroker()

    @Published public var pending: HostKeyChallenge?
    private var continuation: CheckedContinuation<HostKeyDecision, Never>?

    public init() {}

    public func awaitDecision(for challenge: HostKeyChallenge) async -> HostKeyDecision {
        await withCheckedContinuation { cont in
            // Self-heal an orphaned continuation (e.g., sheet failed to
            // present, app backgrounded mid-prompt) so the broker doesn't
            // permanently jam after one bad presentation.
            if let stale = continuation {
                stale.resume(returning: .reject)
                continuation = nil
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

    public nonisolated func makeCallback() -> HostKeyConfirmCallback {
        { @Sendable challenge in
            await self.awaitDecision(for: challenge)
        }
    }
}

// Must be applied to every view that can be topmost when an SSH connect
// starts — at minimum HostListView (sessions) and AddHostView (probe).
// SwiftUI can only present from a visible view, so the cover has to be
// attached where it can actually be reached.
struct HostKeyChallengePresenter: ViewModifier {
    @ObservedObject var broker: HostKeyChallengeBroker = .shared

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $broker.pending) { challenge in
            HostKeyChallengeSheet(challenge: challenge) { decision in
                broker.resolve(decision)
            }
        }
    }
}

extension View {
    func presentingHostKeyChallenge() -> some View {
        modifier(HostKeyChallengePresenter())
    }
}
#endif
