import Foundation

public struct PushSettings: Codable, Hashable, Sendable {
    public var serverURL: String

    public init(serverURL: String) { self.serverURL = serverURL }

    public static let `default` = PushSettings(serverURL: "https://push.sshido.com")
}
