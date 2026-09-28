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

public extension RemoteHost {
    func matches(hostRef ref: String) -> Bool {
        let wanted = ref.lowercased()
        if let learned = remoteHostname { return learned.lowercased() == wanted }
        let shortAddress = hostname.split(separator: ".").first.map { $0.lowercased() }
        return shortAddress == wanted || name.lowercased() == wanted
    }
}

public struct WaitingLedger: Codable, Equatable, Sendable {
    public let pushes: [String: Date]
    public let opened: [UUID: Date]
    public let hostPushes: [String: [String: Date]]
    public let hostVisits: [UUID: Date]

    public init(
        pushes: [String: Date] = [:],
        opened: [UUID: Date] = [:],
        hostPushes: [String: [String: Date]] = [:],
        hostVisits: [UUID: Date] = [:]
    ) {
        self.pushes = pushes
        self.opened = opened
        self.hostPushes = hostPushes
        self.hostVisits = hostVisits
    }

    private enum CodingKeys: String, CodingKey {
        case pushes, opened, hostPushes, hostVisits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pushes: try c.decodeIfPresent([String: Date].self, forKey: .pushes) ?? [:],
            opened: try c.decodeIfPresent([UUID: Date].self, forKey: .opened) ?? [:],
            hostPushes: try c.decodeIfPresent([String: [String: Date]].self, forKey: .hostPushes) ?? [:],
            hostVisits: try c.decodeIfPresent([UUID: Date].self, forKey: .hostVisits) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pushes, forKey: .pushes)
        try c.encode(opened, forKey: .opened)
        try c.encode(hostPushes, forKey: .hostPushes)
        try c.encode(hostVisits, forKey: .hostVisits)
    }

    public func recordingPush(sessionRef: String, hostRef: String, at date: Date) -> WaitingLedger {
        WaitingLedger(
            pushes: sessionRef.isEmpty ? pushes : pushes.merging([sessionRef: date], uniquingKeysWith: max),
            opened: opened,
            hostPushes: hostRef.isEmpty ? hostPushes : hostPushes.merging([hostRef: [sessionRef: date]]) { old, new in
                old.merging(new, uniquingKeysWith: max)
            },
            hostVisits: hostVisits
        )
    }

    public func recordingOpen(_ sessionID: UUID, at date: Date) -> WaitingLedger {
        WaitingLedger(
            pushes: pushes,
            opened: opened.merging([sessionID: date]) { _, new in new },
            hostPushes: hostPushes,
            hostVisits: hostVisits
        )
    }

    public func recordingHostVisit(_ hostID: UUID, at date: Date) -> WaitingLedger {
        WaitingLedger(
            pushes: pushes,
            opened: opened,
            hostPushes: hostPushes,
            hostVisits: hostVisits.merging([hostID: date]) { _, new in new }
        )
    }

    public func isWaiting(_ session: Session) -> Bool {
        let seen = opened[session.id] ?? .distantPast
        return pushes.contains { ref, date in date > seen && session.matches(sessionRef: ref) }
    }

    public func waitingHostIDs(among sessions: [Session], hosts: [RemoteHost]) -> Set<UUID> {
        let viaSessions = sessions.filter(isWaiting).map(\.hostID)
        let viaHostRef = hosts.filter { hasUnmatchedPush(for: $0, knownSessions: sessions) }.map(\.id)
        return Set(viaSessions + viaHostRef)
    }

    private func hasUnmatchedPush(for host: RemoteHost, knownSessions: [Session]) -> Bool {
        let seen = hostVisits[host.id] ?? .distantPast
        return hostPushes.contains { hostRef, bySession in
            host.matches(hostRef: hostRef) && bySession.contains { sessionRef, date in
                date > seen && !Self.isKnown(sessionRef, in: knownSessions)
            }
        }
    }

    private static func isKnown(_ sessionRef: String, in sessions: [Session]) -> Bool {
        !sessionRef.isEmpty && sessions.contains { $0.matches(sessionRef: sessionRef) }
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
        save(Self.recording(userInfo: userInfo, at: date, into: ledger))
    }

    public func markOpened(_ sessionID: UUID, at date: Date = Date()) {
        save(ledger.recordingOpen(sessionID, at: date))
    }

    public func markHostVisited(_ hostID: UUID, at date: Date = Date()) {
        save(ledger.recordingHostVisit(hostID, at: date))
    }

    private static func recording(userInfo: [AnyHashable: Any], at date: Date, into ledger: WaitingLedger) -> WaitingLedger {
        let sessionRef = (userInfo["session_ref"] as? String) ?? ""
        let hostRef = (userInfo["host_ref"] as? String) ?? ""
        return ledger.recordingPush(sessionRef: sessionRef, hostRef: hostRef, at: date)
    }

    #if canImport(UserNotifications)
    public func ingestDeliveredNotifications() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let next = delivered.reduce(ledger) { acc, note in
            Self.recording(userInfo: note.request.content.userInfo, at: note.date, into: acc)
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
