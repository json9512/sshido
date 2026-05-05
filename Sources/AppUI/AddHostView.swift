#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct HostFormData {
    var name = ""
    var hostname = ""
    var port = "22"
    var username = ""
    var authMethod: HostAuthMethod = .key
    var password = ""
    var passwordTouched = false
    var selectedIdentityID: UUID?
}

struct AddHostView: View {
    var existing: RemoteHost?
    var onSaved: (RemoteHost) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = HostFormData()
    @State private var identities: [Identity] = []
    @State private var showAddIdentity = false
    @State private var showManageKeys = false
    @State private var error: String?
    @State private var working = false
    @State private var toast: String?

    init(existing: RemoteHost? = nil, onSaved: @escaping (RemoteHost) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $form.name).autocorrectionDisabled().dsRow()
                    TextField("Host", text: $form.hostname)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().dsRow()
                    TextField("Port", text: $form.port).keyboardType(.numberPad).dsRow()
                    TextField("Username", text: $form.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().dsRow()
                } header: {
                    DSSectionHeader("Connection")
                } footer: {
                    Text("Different networks? Install Tailscale on both devices, then use the peer's MagicDNS name as Host (shape: <host>.<tailnet>.ts.net — find your tailnet in the Tailscale app).")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Section(header: DSSectionHeader("Authentication")) {
                    Picker("Method", selection: $form.authMethod) {
                        Text("Key").tag(HostAuthMethod.key)
                        Text("Password").tag(HostAuthMethod.password)
                    }
                    .pickerStyle(.segmented)
                    .dsRow()
                    if form.authMethod == .key {
                        Picker("Key", selection: $form.selectedIdentityID) {
                            Text("— none —").tag(Optional<UUID>.none)
                            ForEach(identities) { id in
                                Text(id.label).tag(Optional(id.id))
                            }
                        }
                        .dsRow()
                        Button("Add new key…") { showAddIdentity = true }
                            .foregroundStyle(DS.Color.accent).dsRow()
                        if !identities.isEmpty {
                            Button("Manage keys…") { showManageKeys = true }
                                .foregroundStyle(DS.Color.accent).dsRow()
                        }
                    } else {
                        SecureField(existing != nil ? "Password (unchanged if blank)" : "Password",
                                    text: $form.password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: form.password) { _, _ in form.passwordTouched = true }
                            .dsRow()
                    }
                }
                if let error {
                    Section { InlineErrorText(error).dsRow() }
                }
            }
            .dsFormStyle()
            .navigationTitle(existing == nil ? "Add server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Color.textSecondary)
                        .disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if working { ProgressView() } else { Text("Save") }
                    }
                    .disabled(!isValid || working)
                    .coachTarget(.save)
                }
            }
            .dsKeyboardDismissToolbar()
            .task {
                identities = await IdentityStore.shared.all()
                hydrateFromExisting()
                OnboardingCoach.shared.advance(past: .addHost)
            }
            .coachmarks()
            .sheet(isPresented: $showAddIdentity) {
                AddIdentityView { added in
                    identities.append(added)
                    form.selectedIdentityID = added.id
                }
            }
            .sheet(isPresented: $showManageKeys) {
                ManageKeysView()
                    .onDisappear {
                        Task {
                            let fresh = await IdentityStore.shared.all()
                            identities = fresh
                            if let sel = form.selectedIdentityID,
                               !fresh.contains(where: { $0.id == sel }) {
                                form.selectedIdentityID = nil
                            }
                        }
                    }
            }
            .toast($toast)
        }
    }

    private func hydrateFromExisting() {
        guard let h = existing, form.name.isEmpty else { return }
        form.name = h.name
        form.hostname = h.hostname
        form.port = String(h.port)
        form.username = h.username
        form.authMethod = h.authMethod
        form.selectedIdentityID = h.identityID
    }

    private func normalizedHostname(_ s: String) -> String {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://", "ssh://"] {
            if h.lowercased().hasPrefix(scheme) { h.removeFirst(scheme.count) }
        }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        return h
    }

    private var isValid: Bool {
        guard !form.name.isEmpty, !form.hostname.isEmpty, !form.username.isEmpty, Int(form.port) != nil else { return false }
        switch form.authMethod {
        case .key: return form.selectedIdentityID != nil
        case .password:
            if existing != nil { return true }
            return !form.password.isEmpty
        }
    }

    private func save() async {
        error = nil
        working = true
        defer { working = false }

        let hostID = existing?.id ?? UUID()
        let cleanedHost = normalizedHostname(form.hostname)
        let host = RemoteHost(
            id: hostID,
            name: form.name,
            hostname: cleanedHost,
            port: Int(form.port) ?? 22,
            username: form.username,
            identityID: form.authMethod == .key ? form.selectedIdentityID : nil,
            authMethod: form.authMethod,
            useTmux: true,
            tmuxSession: existing?.tmuxSession ?? "sshido",
            agentProfileID: nil
        )

        let auth: SSHAuth
        do {
            auth = try await resolveAuth(for: host)
        } catch {
            self.error = "Auth setup failed: \(error)"
            return
        }

        toast = "Testing connection…"

        let probe = CitadelSSHChannel(
            host: host.hostname,
            port: host.port,
            user: host.username,
            auth: auth,
            cols: 80, rows: 24,
            bootstrapCommand: nil,
            environment: [:]
        )
        do {
            try await probe.connect()
            await probe.disconnect()
        } catch let e as SSHError {
            self.error = friendly(e)
            toast = nil
            return
        } catch {
            self.error = String(describing: error)
            toast = nil
            return
        }

        do {
            if form.authMethod == .password, form.passwordTouched, !form.password.isEmpty {
                try KeychainKeyStore().storePassword(form.password, hostID: host.id)
            }
            if form.authMethod == .key {
                KeychainKeyStore().deletePassword(hostID: host.id)
            }
            try await HostStore.shared.upsert(host)
            toast = "Connected ✓"
            try? await Task.sleep(nanoseconds: 700_000_000)
            onSaved(host)
            dismiss()
        } catch {
            self.error = "Save failed: \(error)"
        }
    }

    private func resolveAuth(for host: RemoteHost) async throws -> SSHAuth {
        switch form.authMethod {
        case .password:
            if form.passwordTouched, !form.password.isEmpty {
                return .password(form.password)
            }
            let existing = try KeychainKeyStore().loadPassword(hostID: host.id)
            return .password(existing)
        case .key:
            guard let identityID = form.selectedIdentityID else {
                throw SSHError.invalidKey("no key selected")
            }
            let pem = try await IdentityStore.shared.loadPEM(for: identityID)
            return .privateKeyPEM(pem, passphrase: nil)
        }
    }

    private func friendly(_ e: SSHError) -> String {
        switch e {
        case .authFailed(let m):
            return "Authentication failed — \(m)"
        case .transport(let m):
            let lower = m.lowercased()
            if lower.contains("timed out") || lower.contains("connect timeout") || lower.contains("connection timed out") {
                if form.hostname.lowercased().hasSuffix(".ts.net") {
                    return "Couldn't reach \(form.hostname):\(form.port) — check that Tailscale is connected on this device and the peer is online"
                }
                return "Couldn't reach \(form.hostname):\(form.port) — host unreachable or blocked"
            }
            if m.contains("NIOConnectionError") || m.contains("refused") {
                return "Connection refused at \(form.hostname):\(form.port) — is SSH running on that port?"
            }
            return "Transport error: \(m)"
        case .invalidKey(let m):
            return "Key problem: \(m)"
        case .notConnected:
            return "Not connected"
        }
    }

}
#endif
