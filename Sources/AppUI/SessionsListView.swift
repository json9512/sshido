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

private struct SessionStatusDot: View {
    let isConnected: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.green.opacity(isConnected ? 0.4 : 0), lineWidth: 4)
                    .scaleEffect(pulsing ? 2.0 : 1.0)
                    .opacity(pulsing ? 0 : 0.4)
            )
            .onAppear {
                if isConnected {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
            }
            .onChange(of: isConnected) { _, connected in
                pulsing = false
                if connected {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
            }
    }
}

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
                }
            }
            if !sessions.isEmpty {
                Section("Open sessions") {
                    ForEach(sessions) { session in
                        NavigationLink(value: AppRouter.Destination.session(session)) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Image(systemName: "terminal.fill")
                                        .font(.title3).foregroundStyle(.tint)
                                    SessionStatusDot(
                                        isConnected: connectedIDs.contains(session.id)
                                    )
                                    .offset(x: 10, y: -10)
                                }
                                .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.headline)
                                        .dynamicTypeSize(.xSmall ... .accessibility2)
                                    Text(session.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                let sid = session.id
                                Task {
                                    await SessionStore.shared.close(sessionID: sid)
                                    await MainActor.run { BridgeStore.shared.remove(sessionID: sid) }
                                    await reload()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            if let error {
                Section { InlineErrorText(error) }
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reload() }
        }
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
            router.push(.session(session))
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif
