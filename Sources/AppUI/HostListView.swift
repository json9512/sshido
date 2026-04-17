#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

private struct PulsingDot: View {
    let active: Bool
    @State private var pulse = false
    var body: some View {
        let color: Color = active ? .green : .secondary
        ZStack {
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 6)
                .frame(width: 10, height: 10)
                .scaleEffect(active && pulse ? 2.2 : 1)
                .opacity(active && pulse ? 0 : 0.5)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .frame(width: 24, height: 24)
        .onAppear {
            guard active else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onChange(of: active) { _, new in
            pulse = false
            guard new else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

public struct HostListView: View {
    @State private var hosts: [RemoteHost] = []
    @State private var connectedHosts: Set<UUID> = []
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
                }
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
        .onChange(of: deepLinks.pendingSessionRef) { _, _ in
            Task { await handleDeepLink() }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .settings:
                NavigationStack { SettingsView() }
            case .addHost:
                AddHostView { _ in Task { await reload() } }
            case .editHost(let host):
                AddHostView(existing: host) { _ in Task { await reload() } }
            }
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
            ContentUnavailableView("Select a server", systemImage: "server.rack")
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if hosts.isEmpty {
                ContentUnavailableView(label: {
                    Label("No servers yet", systemImage: "server.rack")
                }, description: {
                    VStack(spacing: 8) {
                        Text("Tap + to add a server.")
                        Text("Use a private key or a password. For remote access over LTE, install Tailscale on both devices and use the tailnet hostname.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }, actions: {
                    Button { router.sheet = .addHost } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                })
            } else if sizeClass == .regular {
                List(selection: Binding(
                    get: { router.selectedHost },
                    set: { router.selectedHost = $0; router.detailPath.removeAll() }
                )) {
                    ForEach(hosts) { host in
                        hostRow(host).tag(host)
                    }
                    .onDelete { offsets in
                        Task {
                            for i in offsets { try? await HostStore.shared.remove(id: hosts[i].id) }
                            await reload()
                        }
                    }
                }
            } else {
                List {
                    ForEach(hosts) { host in
                        Button {
                            router.push(.host(host))
                        } label: {
                            hostRow(host)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    try? await HostStore.shared.remove(id: host.id)
                                    KeychainKeyStore().deletePassword(hostID: host.id)
                                    await reload()
                                }
                            } label: { Image(systemName: "trash") }
                            Button {
                                router.sheet = .editHost(host)
                            } label: { Image(systemName: "pencil") }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.sheet = .settings } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .addHost } label: { Image(systemName: "plus") }
            }
        }
    }

    @ViewBuilder
    private func hostRow(_ host: RemoteHost) -> some View {
        let connected = connectedHosts.contains(host.id)
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.name).font(.headline)
                    if let pid = host.agentProfileID,
                       let p = AgentProfile.builtins.first(where: { $0.id == pid }) {
                        AgentChip(profile: p)
                    }
                }
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PulsingDot(active: connected)
                .padding(.trailing, 4)
                .accessibilityLabel(connected ? "Connected" : "Not connected")
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        hosts = await HostStore.shared.all()
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
#endif
