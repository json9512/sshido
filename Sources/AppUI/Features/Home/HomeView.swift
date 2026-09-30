#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

extension Notification.Name {
    static let hostsDidChange = Notification.Name("sshido.hostsDidChange")
}

private struct SplitLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeIsSplit: Bool {
        get { self[SplitLayoutKey.self] }
        set { self[SplitLayoutKey.self] = newValue }
    }
}

public struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.services) private var services
    @Environment(\.features) private var features
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @ObservedObject private var agentMode = AgentModeController.shared
    @State private var hosts: [RemoteHost] = []

    public init() {}

    public var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack(path: $router.detailPath) {
                        detailRoot.navigationDestination(for: AppRouter.Destination.self, destination: destination)
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $router.path) {
                    sidebar.navigationDestination(for: AppRouter.Destination.self, destination: destination)
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hostsDidChange)) { _ in Task { await reload() } }
        .onChange(of: deepLinks.pendingSessionRef) { _, _ in Task { await handleDeepLink() } }
        .modifier(SheetOrFullScreen(item: $router.sheet, sizeClass: sizeClass) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .addHost:
                AddHostView { _ in
                    OnboardingCoach.shared.advance(past: .save)
                    NotificationCenter.default.post(name: .hostsDidChange, object: nil)
                }
            case .editHost(let host):
                AddHostView(existing: host) { _ in NotificationCenter.default.post(name: .hostsDidChange, object: nil) }
            }
        })
        .coachmarks()
    }

    private var sidebar: some View {
        List {
            Section {
                EmptyView()
            } header: {
                Text("sshido")
                    .font(DS.Font.display)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textCase(nil)
                    .padding(.top, DS.Spacing.sm)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(features.homeEntries) { entry in
                entry.content()
            }
        }
        .tideList()
        .environment(\.homeIsSplit, sizeClass == .regular)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ToolbarIcon(systemName: "gearshape", label: "Settings") { router.sheet = .settings }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIcon(systemName: "plus", label: "Add server", tint: DS.Color.accent) { router.sheet = .addHost }
                    .coachTarget(hosts.isEmpty ? .addHost : nil)
            }
        }
        .toolbarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destination(_ dest: AppRouter.Destination) -> some View {
        switch dest {
        case .host(let host):
            SessionsListView(host: host)
        case .session(let session):
            if let host = hosts.first(where: { $0.id == session.hostID }) {
                SessionView(session: session, host: host)
            } else {
                EmptyStateView(title: "Server removed")
            }
        case .performance(let host):
            ServerPerformanceView(host: host)
        case .agentChat:
            AgentChatsView()
        case .agentConversation(let id):
            AgentChatView(chatID: id)
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        if let host = router.selectedHost {
            SessionsListView(host: host)
        } else {
            EmptyStateView(title: hosts.isEmpty ? "No servers" : "Pick a server")
                .tideScreen()
        }
    }

    private func reload() async {
        hosts = await services.hosts.all()
        OnboardingCoach.shared.startIfNeeded(hostCount: hosts.count)
        await handleDeepLink()
    }

    private func handleDeepLink() async {
        guard deepLinks.pendingSessionRef != nil else { return }
        if deepLinks.pendingIsAgentChat {
            _ = deepLinks.consume()
            if agentMode.settings.enabled { router.openAgentChats(regular: sizeClass == .regular) }
            return
        }
        let sessions = await services.sessions.allSessions()
        guard let (host, session) = deepLinks.resolve(sessions: sessions, hosts: hosts) else { return }
        _ = deepLinks.consume()
        router.openSession(session, host: host)
    }
}

private struct SheetOrFullScreen<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let sizeClass: UserInterfaceSizeClass?
    @ViewBuilder let content: (Item) -> SheetContent

    func body(content parent: Content) -> some View {
        if sizeClass == .regular {
            parent.fullScreenCover(item: $item) { content($0).tideScreen() }
        } else {
            parent.sheet(item: $item) { content($0) }
        }
    }
}
#endif
