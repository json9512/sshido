import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

@MainActor
public final class AppRouter: ObservableObject {
    public static let shared = AppRouter()

    @Published public var path: [Destination] = []
    @Published public var detailPath: [Destination] = []
    @Published public var selectedHost: RemoteHost?
    @Published public var sheet: Sheet?

    public enum Destination: Hashable {
        case host(RemoteHost)
        case session(Session)
        case performance(RemoteHost)
        case agentChat
        case agentConversation(String)
    }

    public enum Sheet: Identifiable {
        case settings
        case addHost
        case editHost(RemoteHost)

        public var id: String {
            switch self {
            case .settings: return "settings"
            case .addHost: return "addHost"
            case .editHost(let h): return "editHost-\(h.id.uuidString)"
            }
        }
    }

    public init() {}

    public func push(_ d: Destination) {
        path.append(d)
    }

    public func pushSession(_ session: Session, host: RemoteHost) {
        path.append(.session(session))
        detailPath.append(.session(session))
    }

    public func openAgentChats(regular: Bool) {
        if regular {
            selectedHost = nil
            detailPath = [.agentChat]
        } else {
            path = [.agentChat]
        }
    }

    public func openHost(_ host: RemoteHost, regular: Bool) {
        if regular {
            selectedHost = host
            detailPath = []
        } else {
            path.append(.host(host))
        }
    }

    public var agentChatsOpenInDetail: Bool { selectedHost == nil && detailPath.first == .agentChat }

    public func openSession(_ session: Session, host: RemoteHost) {
        selectedHost = host
        path = [.host(host), .session(session)]
        detailPath = [.session(session)]
    }
}
