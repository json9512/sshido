import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public struct AgentModeSettingsStore: Sendable {
    public static let key = "sshido.agentMode.settings"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load() -> AgentModeSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(AgentModeSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AgentModeSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }
}
