#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

public struct HostListView: View {
    @State private var hosts: [RemoteHost] = []
    @State private var path = NavigationPath()
    @State private var showAdd = false
    @State private var editing: RemoteHost?
    @State private var selectedHost: RemoteHost?
    @StateObject private var router = DeepLinkRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init() {}

    public var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    if let host = selectedHost {
                        SessionsListView(host: host)
                    } else {
                        ContentUnavailableView("Select a server", systemImage: "server.rack")
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    sidebar
                        .navigationDestination(for: RemoteHost.self) { host in
                            SessionsListView(host: host)
                        }
                        .navigationDestination(for: Session.self) { session in
                            if let host = hosts.first(where: { $0.id == session.hostID }) {
                                SessionView(session: session, host: host)
                            } else {
                                Text("Host not found").foregroundStyle(.secondary)
                            }
                        }
                }
            }
        }
        .task { await reload() }
        .onChange(of: router.pendingSessionRef) { _, _ in
            Task { await handleDeepLink() }
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
                    Button { showAdd = true } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                })
            } else if sizeClass == .regular {
                List(selection: $selectedHost) {
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
                            path.append(host)
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
                                editing = host
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
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddHostView { _ in Task { await reload() } }
        }
        .sheet(item: $editing) { host in
            AddHostView(existing: host) { _ in Task { await reload() } }
        }
    }

    @ViewBuilder
    private func hostRow(_ host: RemoteHost) -> some View {
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
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        hosts = await HostStore.shared.all()
        await handleDeepLink()
    }

    private func handleDeepLink() async {
        guard router.pendingSessionRef != nil else { return }
        let allSessions = await SessionStore.shared.allSessions()
        if let (host, session) = router.resolve(sessions: allSessions, hosts: hosts) {
            _ = router.consume()
            await MainActor.run {
                path = NavigationPath()
                path.append(host)
                path.append(session)
            }
        }
    }
}
#endif
