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
    @State private var sessions: [Session] = []
    @State private var connectedIDs: Set<UUID> = []
    @State private var remoteSessions: [RemoteTmuxSession] = []
    @State private var error: String?
    @State private var pending: PendingAction?
    @State private var infoSession: Session?
    @EnvironmentObject private var router: AppRouter

    private enum PendingAction: Identifiable {
        case detach(Session)
        case kill(Session)

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
        List {
            Section {
                Button {
                    Task { await openNew() }
                } label: {
                    Label("New session", systemImage: "plus.circle.fill")
                        .foregroundStyle(DS.Color.accent)
                }
                .dsRow()
                .coachTarget(.newSession)
                NavigationLink(value: AppRouter.Destination.performance(host)) {
                    Label("Server performance", systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .dsRow()
            }
            if !sessions.isEmpty {
                Section(header: DSSectionHeader("Open sessions")) {
                    ForEach(sessions) { session in
                        NavigationLink(value: AppRouter.Destination.session(session)) {
                            HStack(spacing: DS.Spacing.md) {
                                ZStack {
                                    Image(systemName: "terminal.fill")
                                        .font(.title3).foregroundStyle(DS.Color.titanium)
                                    DSStatusIndicator(style: .dot(active: connectedIDs.contains(session.id)))
                                        .scaleEffect(0.7)
                                        .offset(x: 10, y: -10)
                                }
                                .frame(width: 24)
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    Text(session.displayName(on: host))
                                        .font(DS.Font.headline)
                                        .foregroundStyle(DS.Color.textPrimary)
                                        .dynamicTypeSize(.xSmall ... .accessibility2)
                                    Text(session.createdAt.formatted(.relative(presentation: .named)))
                                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                }
                            }
                        }
                        .dsRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pending = .kill(session)
                            } label: {
                                Label("Kill", systemImage: "trash").labelStyle(.iconOnly)
                            }
                            .tint(DS.Color.error)
                            Button {
                                pending = .detach(session)
                            } label: {
                                Label("Detach", systemImage: "eject").labelStyle(.iconOnly)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                infoSession = session
                            } label: {
                                Label("Info", systemImage: "info.circle").labelStyle(.iconOnly)
                            }
                            .tint(DS.Color.accent)
                        }
                    }
                }
            }
            if !remoteSessions.isEmpty {
                Section(header: DSSectionHeader("On this server")) {
                    ForEach(remoteSessions) { remote in
                        Button {
                            Task { await adopt(remote) }
                        } label: {
                            HStack(spacing: DS.Spacing.md) {
                                ZStack {
                                    Image(systemName: "terminal")
                                        .font(.title3).foregroundStyle(DS.Color.textSecondary)
                                    DSStatusIndicator(style: .dot(active: remote.attached))
                                        .scaleEffect(0.7)
                                        .offset(x: 10, y: -10)
                                }
                                .frame(width: 24)
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    Text(remote.name)
                                        .font(DS.Font.headline)
                                        .foregroundStyle(DS.Color.textPrimary)
                                        .dynamicTypeSize(.xSmall ... .accessibility2)
                                    Text("\(remote.windows) window\(remote.windows == 1 ? "" : "s") · \(remote.createdAt.formatted(.relative(presentation: .named)))")
                                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                }
                            }
                        }
                        .dsRow()
                    }
                }
            }
            if let error {
                Section { InlineErrorText(error) }
            }
        }
        .dsFormStyle()
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            OnboardingCoach.shared.advance(past: .tapHost)
            await sweep()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await reload()
                await sweep()
            }
        }
        .coachmarks()
        .sheet(item: $infoSession) { session in
            SessionInfoSheet(
                session: session,
                host: host,
                connected: connectedIDs.contains(session.id)
            ) { newName in
                let auth = try await resolveAuth()
                let updated = try await SessionStore.shared.renameSession(
                    session, host: host, auth: auth, to: newName
                )
                await reload()
                return updated
            }
        }
        .confirmationDialog(
            pending.map { ($0.isKill ? "Kill " : "Detach from ") + $0.session.displayName(on: host) + "?" } ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            if action.isKill {
                Button("Kill session", role: .destructive) {
                    Task { await kill(action.session) }
                    pending = nil
                }
            } else {
                Button("Detach") {
                    Task { await detach(action.session) }
                    pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { action in
            Text(action.isKill
                 ? "Ends the tmux session on the server and stops whatever is running inside it. This cannot be undone."
                 : "Disconnects this device. The tmux session keeps running on the server and stays listed under \"On this server\".")
        }
    }

    private func reload() async {
        sessions = await SessionStore.shared.sessions(for: host.id)
        connectedIDs = await SessionStore.shared.connectedSessionIDs(for: host.id)
    }

    private func openNew() async {
        do {
            let auth = try await resolveAuth()
            let session = await SessionStore.shared.openSession(for: host, auth: auth)
            await reload()
            OnboardingCoach.shared.advance(past: .newSession)
            router.push(.session(session))
        } catch {
            self.error = String(describing: error)
        }
    }

    private func adopt(_ remote: RemoteTmuxSession) async {
        do {
            let auth = try await resolveAuth()
            let session = await SessionStore.shared.adoptRemoteSession(for: host, auth: auth, remote: remote)
            remoteSessions.removeAll { $0.name == remote.name }
            await reload()
            router.push(.session(session))
        } catch {
            self.error = String(describing: error)
        }
    }

    private func detach(_ session: Session) async {
        await SessionStore.shared.close(sessionID: session.id)
        BridgeStore.shared.remove(sessionID: session.id)
        await reload()
        await sweep()
    }

    private func kill(_ session: Session) async {
        do {
            let auth = try await resolveAuth()
            try await SessionStore.shared.killRemoteSession(session, host: host, auth: auth)
            BridgeStore.shared.remove(sessionID: session.id)
        } catch {
            self.error = String(describing: error)
        }
        await reload()
        await sweep()
    }

    private func sweep() async {
        guard host.useTmux else { return }
        do {
            let auth = try await resolveAuth()
            remoteSessions = try await SessionStore.shared.syncRemoteSessions(for: host, auth: auth)
            await reload()
        } catch {
            remoteSessions = []
            Log.session.error("tmux sweep failed host=\(host.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func resolveAuth() async throws -> SSHAuth {
        switch host.authMethod {
        case .password:
            return .password(try KeychainKeyStore().loadPassword(hostID: host.id))
        case .key:
            guard let identityID = host.identityID else {
                throw SSHError.invalidKey("host has no key attached (authMethod=.key)")
            }
            let pem = try await IdentityStore.shared.loadPEM(for: identityID)
            return .privateKeyPEM(pem, passphrase: nil)
        }
    }
}
#endif
