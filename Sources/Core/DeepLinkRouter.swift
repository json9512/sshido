import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

@MainActor
public final class DeepLinkRouter: ObservableObject {
    public static let shared = DeepLinkRouter()

    @Published public var pendingSessionRef: String?

    public init() {}

    public func handleNotification(userInfo: [AnyHashable: Any]) {
        if let ref = userInfo["session_ref"] as? String, !ref.isEmpty {
            self.pendingSessionRef = ref
        }
    }

    public func consume() -> String? {
        let ref = pendingSessionRef
        pendingSessionRef = nil
        return ref
    }

    public func resolve(sessions: [Session], hosts: [RemoteHost]) -> (RemoteHost, Session)? {
        guard let ref = pendingSessionRef else { return nil }
        for session in sessions {
            let shortID = String(session.id.uuidString.prefix(8))
            if ref == shortID || ref.hasSuffix("-" + shortID) {
                if let host = hosts.first(where: { $0.id == session.hostID }) {
                    return (host, session)
                }
            }
        }
        return nil
    }
}
