import Foundation

public struct PushSettings: Codable, Hashable, Sendable {
    public var serverURL: String
    public var notificationsEnabled: Bool

    public init(serverURL: String, notificationsEnabled: Bool = true) {
        self.serverURL = serverURL
        self.notificationsEnabled = notificationsEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.serverURL = try c.decode(String.self, forKey: .serverURL)
        self.notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }

    public static let `default` = PushSettings(serverURL: "https://push.sshido.com")
}
