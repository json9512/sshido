import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

public extension Session {
    func matches(sessionRef ref: String) -> Bool {
        let shortID = String(id.uuidString.prefix(8))
        return ref == shortID || ref.hasSuffix("-" + shortID) || ref == tmuxName
    }
}

public struct WaitingLedger: Codable, Equatable, Sendable {
    public let pushes: [String: Date]
    public let opened: [UUID: Date]

    public init(pushes: [String: Date] = [:], opened: [UUID: Date] = [:]) {
        self.pushes = pushes
        self.opened = opened
    }

    public func recordingPush(ref: String, at date: Date) -> WaitingLedger {
        let latest = max(pushes[ref] ?? .distantPast, date)
        return WaitingLedger(pushes: pushes.merging([ref: latest]) { _, new in new }, opened: opened)
    }

    public func recordingOpen(_ sessionID: UUID, at date: Date) -> WaitingLedger {
        WaitingLedger(pushes: pushes, opened: opened.merging([sessionID: date]) { _, new in new })
    }

    public func isWaiting(_ session: Session) -> Bool {
        let seen = opened[session.id] ?? .distantPast
        return pushes.contains { ref, date in date > seen && session.matches(sessionRef: ref) }
    }

    public func waitingHostIDs(among sessions: [Session]) -> Set<UUID> {
        Set(sessions.filter(isWaiting).map(\.hostID))
    }
}

@MainActor
public final class WaitingSessionsStore: ObservableObject {
    public static let shared = WaitingSessionsStore()

    private static let defaultsKey = "sshido.waitingLedger"

    @Published public private(set) var ledger: WaitingLedger

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ledger = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(WaitingLedger.self, from: $0) } ?? WaitingLedger()
    }

    public func isWaiting(_ session: Session) -> Bool {
        ledger.isWaiting(session)
    }

    public func recordPush(userInfo: [AnyHashable: Any], at date: Date) {
        guard let ref = userInfo["session_ref"] as? String, !ref.isEmpty else { return }
        save(ledger.recordingPush(ref: ref, at: date))
    }

    public func markOpened(_ sessionID: UUID, at date: Date = Date()) {
        save(ledger.recordingOpen(sessionID, at: date))
    }

    #if canImport(UserNotifications)
    public func ingestDeliveredNotifications() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let next = delivered.reduce(ledger) { acc, note in
            guard let ref = note.request.content.userInfo["session_ref"] as? String, !ref.isEmpty else { return acc }
            return acc.recordingPush(ref: ref, at: note.date)
        }
        save(next)
    }
    #endif

    private func save(_ next: WaitingLedger) {
        guard next != ledger else { return }
        ledger = next
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
