#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

public struct HostListView: View {
    @State private var hosts: [RemoteHost] = []
    @State private var connectedHosts: Set<UUID> = []
    @State private var pendingHostDelete: RemoteHost?
    @EnvironmentObject private var router: AppRouter
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack(path: $router.detailPath) {
                        detailRoot
                            .navigationDestination(for: AppRouter.Destination.self, destination: destination)
                    }
                    .background(DS.Color.surface0)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $router.path) {
                    sidebar
                        .navigationDestination(for: AppRouter.Destination.self, destination: destination)
                }
            }
        }
        .task { await reload() }
        .onChange(of: scenePhase) { _, new in
            if new == .active { Task { await refreshConnections() } }
        }
        .onChange(of: router.path) { _, _ in
            Task { await refreshConnections() }
        }
        .onChange(of: deepLinks.pendingSessionRef) { _, _ in
            Task { await handleDeepLink() }
        }
        .modifier(SheetOrFullScreen(item: $router.sheet, sizeClass: sizeClass) { sheet in
            switch sheet {
            case .settings:
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { router.sheet = nil }
                            }
                        }
                }
            case .addHost:
                AddHostView { _ in
                    OnboardingCoach.shared.advance(past: .save)
                    Task { await reload() }
                }
            case .editHost(let host):
                AddHostView(existing: host) { _ in Task { await reload() } }
            case .paywall(let ctx):
                PaywallView(context: ctx)
            }
        })
        .coachmarks()
        .confirmationDialog(
            pendingHostDelete.map { "Delete \($0.name)?" } ?? "Delete server?",
            isPresented: Binding(
                get: { pendingHostDelete != nil },
                set: { if !$0 { pendingHostDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingHostDelete
        ) { host in
            Button("Delete", role: .destructive) {
                let hostID = host.id
                Task {
                    try? await HostStore.shared.remove(id: hostID)
                    KeychainKeyStore().deletePassword(hostID: hostID)
                    await reload()
                }
                pendingHostDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingHostDelete = nil }
        } message: { _ in
            Text("This removes the server from this device and deletes any saved password. This cannot be undone.")
        }
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
                ContentUnavailableView("Host missing", systemImage: "server.rack")
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        if let host = router.selectedHost {
            SessionsListView(host: host)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.surface0)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if hosts.isEmpty {
                ContentUnavailableView(label: {
                    Label("No servers yet", systemImage: "server.rack")
                }, description: {
                    VStack(spacing: DS.Spacing.sm) {
                        Text("Tap + to add a server.")
                        Text("Use a private key or a password. For remote access over LTE, install Tailscale on both devices and use the tailnet hostname.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.xl)
                    }
                }, actions: {
                    Button { router.sheet = .addHost } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .coachTarget(.addHost)
                })
            } else if sizeClass == .regular {
                List(selection: Binding(
                    get: { router.selectedHost },
                    set: { router.selectedHost = $0; router.detailPath.removeAll() }
                )) {
                    ForEach(hosts) { host in
                        hostRow(host).tag(host).dsRow()
                    }
                    .onDelete { offsets in
                        guard let idx = offsets.first else { return }
                        pendingHostDelete = hosts[idx]
                    }
                }
            } else {
                List {
                    ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                        Button {
                            router.push(.host(host))
                        } label: {
                            hostRow(host)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .dsRow()
                        .coachTarget(index == 0 ? .tapHost : nil)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingHostDelete = host
                            } label: { Label("Delete", systemImage: "trash").labelStyle(.iconOnly) }
                            .tint(DS.Color.error)
                            Button {
                                router.sheet = .editHost(host)
                            } label: { Label("Edit", systemImage: "pencil").labelStyle(.iconOnly) }
                            .tint(DS.Color.accent)
                        }
                    }
                }
            }
        }
        .dsFormStyle()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.sheet = .settings } label: {
                    Image(systemName: "gearshape")
                }
                .tint(DS.Color.titaniumLight)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .addHost } label: {
                    Image(systemName: "plus")
                }
                .tint(DS.Color.titaniumLight)
            }
        }
    }

    @ViewBuilder
    private func hostRow(_ host: RemoteHost) -> some View {
        let connected = connectedHosts.contains(host.id)
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(DS.Color.titanium)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(host.name).font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    if let pid = host.agentProfileID,
                       let p = AgentProfile.builtins.first(where: { $0.id == pid }) {
                        AgentChip(profile: p)
                    }
                }
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSStatusIndicator(style: .dot(active: connected))
                .padding(.trailing, DS.Spacing.xs)
                .accessibilityLabel(connected ? "Connected" : "Not connected")
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private func reload() async {
        hosts = await HostStore.shared.all()
        OnboardingCoach.shared.startIfNeeded(hostCount: hosts.count)
        await refreshConnections()
        await handleDeepLink()
    }

    private func refreshConnections() async {
        connectedHosts = await SessionStore.shared.connectedHostIDs()
    }

    private func handleDeepLink() async {
        guard deepLinks.pendingSessionRef != nil else { return }
        let allSessions = await SessionStore.shared.allSessions()
        if let (host, session) = deepLinks.resolve(sessions: allSessions, hosts: hosts) {
            _ = deepLinks.consume()
            router.openSession(session, host: host)
        }
    }
}

/// Uses fullScreenCover on iPad (regular width) and sheet on iPhone (compact width).
private struct SheetOrFullScreen<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let sizeClass: UserInterfaceSizeClass?
    @ViewBuilder let content: (Item) -> SheetContent

    func body(content parent: Content) -> some View {
        if sizeClass == .regular {
            parent.fullScreenCover(item: $item) { it in
                content(it)
                    .background(DS.Color.surface0)
            }
        } else {
            parent.sheet(item: $item) { it in
                content(it)
            }
        }
    }
}
#endif
