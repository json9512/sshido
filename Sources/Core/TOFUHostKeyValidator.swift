import Foundation
import NIOCore
import NIOSSH
#if canImport(sshidoModels)
import sshidoModels
#endif

public typealias HostKeyConfirmCallback = @Sendable (HostKeyChallenge) async -> HostKeyDecision

public final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    private let host: String
    private let port: Int
    private let store: KnownHostStore
    private let confirm: HostKeyConfirmCallback

    public init(host: String, port: Int, store: KnownHostStore = .shared, confirm: @escaping HostKeyConfirmCallback) {
        self.host = host
        self.port = port
        self.store = store
        self.confirm = confirm
    }

    public func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = HostKeyFingerprint.sha256(hostKey)
        let host = self.host
        let port = self.port
        let store = self.store
        let confirm = self.confirm

        Task {
            let known = await store.get(host: host, port: port)
            let outcome = await TOFUDecision.decide(
                host: host,
                port: port,
                presented: presented,
                known: known,
                userDecision: confirm
            )
            switch outcome {
            case .accept(.alreadyKnown):
                await store.touchLastSeen(host: host, port: port)
                validationCompletePromise.succeed(())
            case .accept(.newlyTrusted):
                do {
                    try await store.add(host: host, port: port, fingerprint: presented)
                    validationCompletePromise.succeed(())
                } catch {
                    validationCompletePromise.fail(error)
                }
            case .accept(.replaced):
                do {
                    try await store.replace(host: host, port: port, fingerprint: presented)
                    validationCompletePromise.succeed(())
                } catch {
                    validationCompletePromise.fail(error)
                }
            case .reject(let error):
                validationCompletePromise.fail(error)
            }
        }
    }
}

public enum TOFUDecision {
    public enum AcceptReason: Sendable, Equatable {
        case alreadyKnown
        case newlyTrusted
        case replaced
    }

    public enum Outcome: Sendable, Equatable {
        case accept(AcceptReason)
        case reject(HostKeyValidationError)
    }

    public static func decide(
        host: String,
        port: Int,
        presented: String,
        known: KnownHost?,
        userDecision: HostKeyConfirmCallback
    ) async -> Outcome {
        if let known {
            if known.fingerprint == presented {
                return .accept(.alreadyKnown)
            }
            let challenge = HostKeyChallenge.mismatch(host: host, port: port, expected: known.fingerprint, presented: presented)
            switch await userDecision(challenge) {
            case .trust:
                return .accept(.replaced)
            case .reject:
                return .reject(.mismatch(host: host, port: port, expected: known.fingerprint, presented: presented))
            }
        }
        let challenge = HostKeyChallenge.unknownHost(host: host, port: port, fingerprint: presented)
        switch await userDecision(challenge) {
        case .trust:
            return .accept(.newlyTrusted)
        case .reject:
            return .reject(.rejectedByUser(host: host, port: port))
        }
    }
}

public enum HostKeyValidationError: Error, Equatable, Sendable {
    case mismatch(host: String, port: Int, expected: String, presented: String)
    case rejectedByUser(host: String, port: Int)
}
