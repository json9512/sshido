import Foundation
import Network

public enum NetworkStatus: Sendable, Equatable {
    case unknown
    case online
    case offline
}

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()

    @Published public private(set) var status: NetworkStatus = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.sshido.net")
    private var lastChangeHandlers: [@Sendable (NetworkStatus) -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next: NetworkStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor in
                if next != self.status {
                    self.status = next
                    for handler in self.lastChangeHandlers { handler(next) }
                }
            }
        }
        monitor.start(queue: queue)
    }

    public func onChange(_ handler: @escaping @Sendable (NetworkStatus) -> Void) {
        lastChangeHandlers.append(handler)
    }
}
