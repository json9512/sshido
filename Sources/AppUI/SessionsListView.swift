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
    @State private var error: String?
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                let sid = session.id
                                Task {
                                    await SessionStore.shared.close(sessionID: sid)
                                    await MainActor.run { BridgeStore.shared.remove(sessionID: sid) }
                                    await reload()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                            }
                            .tint(DS.Color.error)
                        }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reload() }
        }
        .coachmarks()
    }

    private func reload() async {
        sessions = await SessionStore.shared.sessions(for: host.id)
        connectedIDs = await SessionStore.shared.connectedSessionIDs(for: host.id)
    }

    private func openNew() async {
        do {
            let auth: SSHAuth
            switch host.authMethod {
            case .password:
                let pw = try KeychainKeyStore().loadPassword(hostID: host.id)
                auth = .password(pw)
            case .key:
                guard let identityID = host.identityID else {
                    error = "host has no key attached (authMethod=.key)"
                    return
                }
                let pem = try await IdentityStore.shared.loadPEM(for: identityID)
                auth = .privateKeyPEM(pem, passphrase: nil)
            }
            let session = await SessionStore.shared.openSession(for: host, auth: auth)
            await reload()
            OnboardingCoach.shared.advance(past: .newSession)
            router.push(.session(session))
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif
