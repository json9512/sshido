import Foundation

public struct PushSubscription: Codable, Hashable, Sendable {
    public var serverURL: String
    public var subscriberID: String
    public var notifyURL: String
    public var subscribedAt: Date

    public init(serverURL: String, subscriberID: String, notifyURL: String, subscribedAt: Date = Date()) {
        self.serverURL = serverURL
        self.subscriberID = subscriberID
        self.notifyURL = notifyURL
        self.subscribedAt = subscribedAt
    }
}

public struct PushSettings: Codable, Hashable, Sendable {
    public var serverURL: String

    public init(serverURL: String) { self.serverURL = serverURL }

    public static let `default` = PushSettings(serverURL: "https://push.sshido.app")
}
