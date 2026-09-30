#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

enum SettingsGroup: Int, CaseIterable, Identifiable {
    case connections, agents, terminal, general

    var id: Int { rawValue }

    var title: String? {
        switch self {
        case .connections: return "Connections"
        case .agents: return "Agents"
        case .terminal: return "Terminal"
        case .general: return nil
        }
    }
}

struct SettingsEntry: Identifiable, Sendable {
    let id: String
    let group: SettingsGroup
    let order: Int
    let icon: String
    let title: String
    let summary: @MainActor @Sendable (AppServices) async -> String?
    let destination: @MainActor @Sendable () -> AnyView
}

struct HomeEntry: Identifiable, Sendable {
    let id: String
    let order: Int
    let title: String?
    let content: @MainActor @Sendable () -> AnyView
}

protocol AppFeature: Sendable {
    var id: String { get }
    var settings: [SettingsEntry] { get }
    var home: [HomeEntry] { get }
}

extension AppFeature {
    var settings: [SettingsEntry] { [] }
    var home: [HomeEntry] { [] }
}

struct FeatureSet: Sendable {
    let features: [any AppFeature]

    var homeEntries: [HomeEntry] {
        features.flatMap(\.home).sorted { $0.order < $1.order }
    }

    func settings(in group: SettingsGroup) -> [SettingsEntry] {
        features.flatMap(\.settings).filter { $0.group == group }.sorted { $0.order < $1.order }
    }

    static let live = FeatureSet(features: [
        AgentsFeature(),
        ServersFeature(),
        NotificationsFeature(),
        TerminalFeature(),
        GeneralFeature(),
    ])
}

private struct ServicesKey: EnvironmentKey {
    static let defaultValue = AppServices.live
}

private struct FeaturesKey: EnvironmentKey {
    static let defaultValue = FeatureSet.live
}

extension EnvironmentValues {
    var services: AppServices {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }

    var features: FeatureSet {
        get { self[FeaturesKey.self] }
        set { self[FeaturesKey.self] = newValue }
    }
}
#endif
