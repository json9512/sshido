import Foundation

public struct PushToken: Codable, Hashable, Sendable {
    public let deviceToken: String
    public let relayURL: URL
    public let authSecret: String

    public init(deviceToken: String, relayURL: URL, authSecret: String) {
        self.deviceToken = deviceToken
        self.relayURL = relayURL
        self.authSecret = authSecret
    }
}
