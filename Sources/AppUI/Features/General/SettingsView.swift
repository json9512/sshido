#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

struct SettingsView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.features) private var features
    @Environment(\.services) private var services
    @State private var summaries: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsGroup.allCases) { group in
                    let entries = features.settings(in: group)
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                NavigationLink { entry.destination() } label: {
                                    TideRow(icon: entry.icon, title: entry.title, subtitle: summaries[entry.id])
                                }
                                .tideRow()
                            }
                        } header: {
                            if let title = group.title { SectionLabel(title) }
                        }
                    }
                }
            }
            .tideList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheetActions(cancel: { router.sheet = nil })
            .task { await loadSummaries() }
            .onAppear { Task { await loadSummaries() } }
        }
    }

    private func loadSummaries() async {
        let entries = SettingsGroup.allCases.flatMap { features.settings(in: $0) }
        let pairs = await entries.asyncMap { entry in (entry.id, await entry.summary(services)) }
        summaries = Dictionary(uniqueKeysWithValues: pairs.compactMap { id, value in value.map { (id, $0) } })
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var out: [T] = []
        for element in self {
            out = out + [await transform(element)]
        }
        return out
    }
}

struct GeneralFeature: AppFeature {
    let id = "general"

    var settings: [SettingsEntry] {
        [
            SettingsEntry(id: "privacy", group: .general, order: 0, icon: "hand.raised", title: "Privacy",
                          summary: { _ in UserDefaults.standard.object(forKey: SentryBootstrap.enabledKey) as? Bool ?? true ? "Crash reports on" : "Crash reports off" },
                          destination: { AnyView(PrivacySettingsView()) }),
            SettingsEntry(id: "about", group: .general, order: 1, icon: "questionmark.circle", title: "About & help",
                          summary: { _ in AboutView.version },
                          destination: { AnyView(AboutView()) }),
        ]
    }
}

struct PrivacySettingsView: View {
    @AppStorage(SentryBootstrap.enabledKey) private var crashReports = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $crashReports) { TideRow(icon: "ant", title: "Crash reports") }
                    .tideRow()
            } footer: {
                Text("Anonymous. No credentials or terminal content. Applies on next launch.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Section {
                NavigationLink { PrivacyPolicyView() } label: { TideRow(icon: "doc.text", title: "Privacy policy") }
                    .tideRow()
            }
        }
        .tideList()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                NavigationLink { FAQView() } label: { TideRow(icon: "questionmark.bubble", title: "Help & FAQ") }
                    .tideRow()
                NavigationLink { PushGuideView() } label: { TideRow(icon: "bell.badge", title: "Push notifications guide") }
                    .tideRow()
                NavigationLink { AgentSetupGuideView() } label: { TideRow(icon: "person.2.wave.2", title: "Agent host guide") }
                    .tideRow()
            }
            Section {
                link("chevron.left.forwardslash.chevron.right", "Source code", "https://github.com/json9512/sshido")
                link("globe", "sshido.com", "https://sshido.com")
                Button { OnboardingCoach.shared.reset() } label: { TideRow(icon: "arrow.counterclockwise", title: "Show tips again") }
                    .tideRow()
            }
            Section {
                LabeledContent("Version", value: Self.version).font(DS.Font.callout).tideRow()
            }
        }
        .tideList()
        .navigationTitle("About & help")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func link(_ icon: String, _ title: String, _ url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                TideRow(icon: icon, title: title) {
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .tideRow()
        }
    }
}
#endif
