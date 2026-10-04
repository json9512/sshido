#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AddHostView: View {
    var existing: RemoteHost?
    var onSaved: (RemoteHost) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services

    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: HostAuthMethod = .key
    @State private var password = ""
    @State private var passwordTouched = false
    @State private var identityID: UUID?
    @State private var identities: [Identity] = []
    @State private var addingKey = false
    @State private var managingKeys = false
    @State private var error: String?
    @State private var phase: Phase = .editing

    enum Phase: Equatable { case editing, testing, connected }

    init(existing: RemoteHost? = nil, onSaved: @escaping (RemoteHost) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    field("Name", text: $name, icon: "character.cursor.ibeam")
                    field("Host", text: $hostname, icon: "network", keyboard: .URL)
                    field("Port", text: $port, icon: "number", keyboard: .numberPad)
                    field("User", text: $username, icon: "person")
                }
                Section {
                    Picker("Sign in with", selection: $authMethod) {
                        Label("Key", systemImage: "key.horizontal").tag(HostAuthMethod.key)
                        Label("Password", systemImage: "ellipsis.rectangle").tag(HostAuthMethod.password)
                    }
                    .pickerStyle(.segmented)
                    .tideRow()
                    if authMethod == .key { keyRows } else { passwordRow }
                }
                if phase != .editing {
                    Section {
                        HStack(spacing: DS.Spacing.md) {
                            AnimatedGlyph(animation: phase == .connected ? .pass : .connecting, loop: phase == .testing,
                                          size: CGSize(width: 36, height: 36))
                            Text(phase == .connected ? "Connected" : "Connecting to \(hostname)…")
                                .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        }
                        .tideRow()
                    }
                }
                if let error {
                    Section { InlineErrorText(error).tideRow() }
                }
            }
            .tideList()
            .navigationTitle(existing == nil ? "New server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .sheetActions(cancel: { dismiss() }, confirm: { Task { await save() } },
                          confirmEnabled: isValid, working: phase == .testing, confirmCoach: .save)
            .keyboardDismissButton()
            .task {
                identities = await services.identities.all()
                hydrate()
                OnboardingCoach.shared.advance(past: .addHost)
            }
            .sheet(isPresented: $addingKey) {
                AddIdentityView { added in
                    identities = identities + [added]
                    identityID = added.id
                }
            }
            .sheet(isPresented: $managingKeys, onDismiss: { Task { await refreshIdentities() } }) {
                KeysSheet()
            }
        }
        .coachmarks()
        .presentingHostKeyChallenge()
    }

    private func field(_ title: String, text: Binding<String>, icon: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon).foregroundStyle(DS.Color.textTertiary).frame(width: 26)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(keyboard == .default && title == "Name" ? DS.Font.body : DS.Font.monoBody)
        }
        .frame(minHeight: DS.hitTarget)
        .tideRow()
    }

    @ViewBuilder
    private var keyRows: some View {
        Picker(selection: $identityID) {
            Text("None").tag(UUID?.none)
            ForEach(identities) { Text($0.label).tag(UUID?.some($0.id)) }
        } label: {
            TideRow(icon: "key.horizontal", title: "Key")
        }
        .tideRow()
        HStack(spacing: DS.Spacing.sm) {
            Spacer()
            IconButton(systemName: "plus", label: "New key") { addingKey = true }
            if !identities.isEmpty {
                IconButton(systemName: "list.bullet", label: "Manage keys") { managingKeys = true }
            }
        }
        .tideRow()
    }

    private var passwordRow: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "lock").foregroundStyle(DS.Color.textTertiary).frame(width: 26)
            SecureField(existing != nil ? "Unchanged" : "Password", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: password) { _, _ in passwordTouched = true }
        }
        .frame(minHeight: DS.hitTarget)
        .tideRow()
    }

    private func hydrate() {
        guard let h = existing, name.isEmpty else { return }
        name = h.name
        hostname = h.hostname
        port = String(h.port)
        username = h.username
        authMethod = h.authMethod
        identityID = h.identityID
    }

    private func refreshIdentities() async {
        let fresh = await services.identities.all()
        identities = fresh
        if let selected = identityID, !fresh.contains(where: { $0.id == selected }) {
            identityID = nil
        }
    }

    static func normalizedHostname(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = ["http://", "https://", "ssh://"]
            .first { trimmed.lowercased().hasPrefix($0) }
            .map { String(trimmed.dropFirst($0.count)) } ?? trimmed
        return withoutScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutScheme
    }

    private var isValid: Bool {
        guard !name.isEmpty, !hostname.isEmpty, !username.isEmpty, Int(port) != nil else { return false }
        switch authMethod {
        case .key: return identityID != nil
        case .password: return existing != nil || !password.isEmpty
        }
    }

    private func draft() -> RemoteHost {
        let cleaned = Self.normalizedHostname(hostname)
        return RemoteHost(
            id: existing?.id ?? UUID(),
            name: name,
            hostname: cleaned,
            port: Int(port) ?? 22,
            username: username,
            identityID: authMethod == .key ? identityID : nil,
            authMethod: authMethod,
            useTmux: true,
            tmuxSession: existing?.tmuxSession ?? "sshido",
            agentProfileID: nil,
            remoteHostname: existing?.hostname == cleaned ? existing?.remoteHostname : nil
        )
    }

    private func auth(for host: RemoteHost) async throws -> SSHAuth {
        if authMethod == .password, passwordTouched, !password.isEmpty {
            return .password(password)
        }
        return try await services.credentials.auth(for: host)
    }

    private func save() async {
        error = nil
        let host = draft()
        phase = .testing
        do {
            let probe = CitadelSSHChannel(host: host.hostname, port: host.port, user: host.username,
                                          auth: try await auth(for: host), cols: 80, rows: 24,
                                          hostKeyConfirm: HostKeyChallengeBroker.shared.makeCallback())
            try await probe.connect()
            await probe.disconnect()
            try persist(host)
            try await services.hosts.upsert(host)
            phase = .connected
            try? await Task.sleep(for: .milliseconds(900))
            onSaved(host)
            dismiss()
        } catch let e as SSHError {
            phase = .editing
            error = friendly(e)
        } catch {
            phase = .editing
            self.error = error.localizedDescription
        }
    }

    private func persist(_ host: RemoteHost) throws {
        if authMethod == .password, passwordTouched, !password.isEmpty {
            try services.passwords.storePassword(password, hostID: host.id)
        }
        if authMethod == .key {
            services.passwords.deletePassword(hostID: host.id)
        }
    }

    private func friendly(_ e: SSHError) -> String {
        switch e {
        case .authFailed(let m):
            return "Authentication failed: \(m)"
        case .transport(let m):
            let lower = m.lowercased()
            if lower.contains("timed out") || lower.contains("connect timeout") {
                return hostname.lowercased().hasSuffix(".ts.net")
                    ? "Couldn't reach \(hostname):\(port). Is Tailscale connected on this device, and is the peer online?"
                    : "Couldn't reach \(hostname):\(port)."
            }
            if m.contains("NIOConnectionError") || m.contains("refused") {
                return "Connection refused at \(hostname):\(port). Is SSH running on that port?"
            }
            return m
        case .invalidKey(let m):
            return "Key problem: \(m)"
        case .notConnected:
            return "Not connected."
        case .hostKeyChanged(let host, let port, _, _):
            return "The host key for \(host):\(port) changed since you trusted it. Check it in Settings › Servers & keys › Trusted hosts."
        case .hostKeyRejected(let host, let port):
            return "Cancelled: the key for \(host):\(port) wasn't trusted."
        case .hostNotFound:
            return e.description
        }
    }
}
#endif
