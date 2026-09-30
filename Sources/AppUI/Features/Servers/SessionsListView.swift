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

struct SessionsListView: View {
    let host: RemoteHost
    @EnvironmentObject private var router: AppRouter
    @Environment(\.services) private var services
    @ObservedObject private var waiting = WaitingSessionsStore.shared
    @State private var sessions: [Session] = []
    @State private var connectedIDs: Set<UUID> = []
    @State private var remote: [RemoteTmuxSession] = []
    @State private var loaded = false
    @State private var opening = false
    @State private var error: String?
    @State private var pending: PendingAction?
    @State private var infoSession: Session?

    private enum PendingAction: Identifiable {
        case detach(Session), kill(Session)

        var session: Session {
            switch self {
            case .detach(let s), .kill(let s): return s
            }
        }

        var isKill: Bool {
            if case .kill = self { return true }
            return false
        }

        var id: String { "\(isKill ? "kill" : "detach")-\(session.id.uuidString)" }
    }

    var body: some View {
        Group {
            if loaded && sessions.isEmpty && remote.isEmpty && error == nil {
                EmptyStateView(title: "No sessions", action: (icon: "plus", label: "New session", run: { Task { await openNew() } }))
                    .coachTarget(.newSession)
            } else {
                list
            }
        }
        .tideScreen()
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ToolbarIcon(systemName: "gauge.with.dots.needle.50percent", label: "Server performance") {
                    router.push(.performance(host))
                }
                if opening {
                    ProgressView().tint(DS.Color.accent)
                } else {
                    ToolbarIcon(systemName: "plus", label: "New session", tint: DS.Color.accent) { Task { await openNew() } }
                        .coachTarget(sessions.isEmpty ? nil : .newSession)
                }
            }
        }
        .task {
            await reload()
            await waiting.ingestDeliveredNotifications()
            OnboardingCoach.shared.advance(past: .tapHost)
            await sweep()
            await learnRemoteHostname()
        }
        .onAppear { waiting.markHostVisited(host.id) }
        .onDisappear { waiting.markHostVisited(host.id) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await reload()
                await waiting.ingestDeliveredNotifications()
                await sweep()
            }
        }
        .coachmarks()
        .sheet(item: $infoSession) { session in
            SessionInfoSheet(session: session, host: host, connected: connectedIDs.contains(session.id)) { newName in
                let auth = try await services.credentials.auth(for: host)
                let updated = try await services.sessions.renameSession(session, host: host, auth: auth, to: newName)
                await reload()
                return updated
            }
        }
        .confirmationDialog(pending.map { ($0.isKill ? "Kill " : "Detach ") + $0.session.displayName(on: host) + "?" } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { action in
            if action.isKill {
                Button("Kill session", role: .destructive) { Task { await kill(action.session) } }
            } else {
                Button("Detach") { Task { await detach(action.session) } }
            }
        } message: { action in
            Text(action.isKill ? "Stops everything running in it on the server." : "It keeps running on the server.")
        }
    }

    private var list: some View {
        List {
            if !sessions.isEmpty {
                Section {
                    ForEach(sessions) { session in
                        NavigationLink(value: AppRouter.Destination.session(session)) {
                            TideRow(icon: "terminal", title: session.displayName(on: host),
                                    subtitle: session.createdAt.formatted(.relative(presentation: .named))) {
                                StatusDot(color: dotColor(session), pulsing: waiting.isWaiting(session))
                            }
                        }
                        .tideRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { pending = .kill(session) } label: { Label("Kill", systemImage: "trash") }
                                .tint(DS.Color.error)
                            Button { pending = .detach(session) } label: { Label("Detach", systemImage: "eject") }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { infoSession = session } label: { Label("Info", systemImage: "info.circle") }
                                .tint(DS.Color.accent)
                        }
                    }
                } header: {
                    SectionLabel("Open")
                }
            }
            if !remote.isEmpty {
                Section {
                    ForEach(remote) { item in
                        Button { Task { await adopt(item) } } label: {
                            TideRow(icon: "rectangle.stack", title: item.name,
                                    subtitle: "\(item.windows) window\(item.windows == 1 ? "" : "s") · \(item.createdAt.formatted(.relative(presentation: .named)))",
                                    tint: DS.Color.textSecondary) {
                                StatusDot(color: item.attached ? DS.Color.success : DS.Color.textTertiary)
                            }
                        }
                        .tideRow()
                    }
                } header: {
                    SectionLabel("On this server")
                }
            }
            if let error {
                Section { InlineErrorText(error).tideRow() }
            }
        }
        .tideList()
    }

    private func dotColor(_ session: Session) -> Color {
        if waiting.isWaiting(session) { return DS.Color.warning }
        return connectedIDs.contains(session.id) ? DS.Color.success : DS.Color.textTertiary
    }

    private func reload() async {
        sessions = await services.sessions.sessions(for: host.id)
        connectedIDs = await services.sessions.connectedSessionIDs(for: host.id)
        loaded = true
    }

    private func openNew() async {
        opening = true
        defer { opening = false }
        do {
            let auth = try await services.credentials.auth(for: host)
            let session = await services.sessions.openSession(for: host, auth: auth, title: nil)
            await reload()
            OnboardingCoach.shared.advance(past: .newSession)
            router.push(.session(session))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func adopt(_ item: RemoteTmuxSession) async {
        do {
            let auth = try await services.credentials.auth(for: host)
            let session = await services.sessions.adoptRemoteSession(for: host, auth: auth, remote: item)
            remote = remote.filter { $0.name != item.name }
            await reload()
            router.push(.session(session))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func detach(_ session: Session) async {
        await services.sessions.close(sessionID: session.id)
        BridgeStore.shared.remove(sessionID: session.id)
        pending = nil
        await reload()
        await sweep()
    }

    private func kill(_ session: Session) async {
        do {
            let auth = try await services.credentials.auth(for: host)
            try await services.sessions.killRemoteSession(session, host: host, auth: auth)
            BridgeStore.shared.remove(sessionID: session.id)
        } catch {
            self.error = error.localizedDescription
        }
        pending = nil
        await reload()
        await sweep()
    }

    private func learnRemoteHostname() async {
        do {
            let auth = try await services.credentials.auth(for: host)
            guard let name = try await services.sessions.remoteShortHostname(for: host, auth: auth) else {
                Log.session.error("hostname -s returned nothing host=\(host.name, privacy: .public)")
                return
            }
            try await services.hosts.setRemoteHostname(name, for: host.id)
        } catch {
            Log.session.error("hostname probe failed host=\(host.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func sweep() async {
        guard host.useTmux else { return }
        do {
            let auth = try await services.credentials.auth(for: host)
            remote = try await services.sessions.syncRemoteSessions(for: host, auth: auth)
            await reload()
        } catch {
            remote = []
            Log.session.error("tmux sweep failed host=\(host.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
