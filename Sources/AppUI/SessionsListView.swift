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
    @State private var pendingSessionDelete: Session?
    @EnvironmentObject private var router: AppRouter

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
                                    Text(session.title)
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
                                pendingSessionDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                            }
                            .tint(DS.Color.error)
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
        .confirmationDialog(
            pendingSessionDelete.map { "Close \($0.title)?" } ?? "Close session?",
            isPresented: Binding(
                get: { pendingSessionDelete != nil },
                set: { if !$0 { pendingSessionDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingSessionDelete
        ) { session in
            Button("Close session", role: .destructive) {
                let sid = session.id
                Task {
                    await SessionStore.shared.close(sessionID: sid)
                    await MainActor.run { BridgeStore.shared.remove(sessionID: sid) }
                    await reload()
                }
                pendingSessionDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingSessionDelete = nil }
        } message: { _ in
            Text("Disconnects this session. The tmux window on the server remains and can be reopened.")
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

    private func sweep() async {
        guard host.useTmux else { return }
        do {
            let auth = try await resolveAuth()
            remoteSessions = try await SessionStore.shared.listRemoteTmuxSessions(for: host, auth: auth)
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
