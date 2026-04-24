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
    }

    public enum Sheet: Identifiable {
        case settings
        case addHost
        case editHost(RemoteHost)
        case paywall(PaywallContext)

        public var id: String {
            switch self {
            case .settings: return "settings"
            case .addHost: return "addHost"
            case .editHost(let h): return "editHost-\(h.id.uuidString)"
            case .paywall(let ctx): return "paywall-\(ctx)"
            }
        }
    }

    /// Present the paywall if the user lacks sshido+; otherwise run `action`.
    public func requirePlus(_ ctx: PaywallContext, action: () -> Void = {}) {
        if Entitlements.shared.hasPlus {
            action()
        } else {
            sheet = .paywall(ctx)
        }
    }

    /// Present the paywall if the user lacks Cloud Pro; otherwise run `action`.
    public func requireCloudPro(_ ctx: PaywallContext, action: () -> Void = {}) {
        if Entitlements.shared.hasCloudPro {
            action()
        } else {
            sheet = .paywall(ctx)
        }
    }

    public init() {}

    public func push(_ d: Destination) {
        path.append(d)
    }

    public func popToRoot() {
        path.removeAll()
        detailPath.removeAll()
    }

    public func openSession(_ session: Session, host: RemoteHost) {
        selectedHost = host
        path = [.host(host), .session(session)]
        detailPath = [.session(session)]
    }
}
