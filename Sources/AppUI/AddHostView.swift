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

    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: HostAuthMethod = .key
    @State private var password = ""
    @State private var passwordTouched = false
    @State private var identities: [Identity] = []
    @State private var selectedIdentityID: UUID?
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
                    TextField("Name", text: $name).autocorrectionDisabled().dsRow()
                    TextField("Host", text: $hostname)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().dsRow()
                    TextField("Port", text: $port).keyboardType(.numberPad).dsRow()
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().dsRow()
                } header: {
                    DSSectionHeader("Connection")
                } footer: {
                    Text("Different networks? Install Tailscale on both devices, then use the peer's MagicDNS name as Host (shape: <host>.<tailnet>.ts.net — find your tailnet in the Tailscale app).")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Section(header: DSSectionHeader("Authentication")) {
                    Picker("Method", selection: $authMethod) {
                        Text("Key").tag(HostAuthMethod.key)
                        Text("Password").tag(HostAuthMethod.password)
                    }
                    .pickerStyle(.segmented)
                    .dsRow()
                    if authMethod == .key {
                        Picker("Key", selection: $selectedIdentityID) {
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
                                    text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: password) { _, _ in passwordTouched = true }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .task {
                identities = await IdentityStore.shared.all()
                hydrateFromExisting()
                OnboardingCoach.shared.advance(past: .addHost)
            }
            .coachmarks()
            .sheet(isPresented: $showAddIdentity) {
                AddIdentityView { added in
                    identities.append(added)
                    selectedIdentityID = added.id
                }
            }
            .sheet(isPresented: $showManageKeys) {
                ManageKeysView()
                    .onDisappear {
                        Task {
                            let fresh = await IdentityStore.shared.all()
                            identities = fresh
                            if let sel = selectedIdentityID,
                               !fresh.contains(where: { $0.id == sel }) {
                                selectedIdentityID = nil
                            }
                        }
                    }
            }
            .toast($toast)
        }
    }

    private func hydrateFromExisting() {
        guard let h = existing, name.isEmpty else { return }
        name = h.name
        hostname = h.hostname
        port = String(h.port)
        username = h.username
        authMethod = h.authMethod
        selectedIdentityID = h.identityID
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
        guard !name.isEmpty, !hostname.isEmpty, !username.isEmpty, Int(port) != nil else { return false }
        switch authMethod {
        case .key: return selectedIdentityID != nil
        case .password:
            if existing != nil { return true }
            return !password.isEmpty
        }
    }

    private func save() async {
        error = nil
        working = true
        defer { working = false }

        let hostID = existing?.id ?? UUID()
        let cleanedHost = normalizedHostname(hostname)
        let host = RemoteHost(
            id: hostID,
            name: name,
            hostname: cleanedHost,
            port: Int(port) ?? 22,
            username: username,
            identityID: authMethod == .key ? selectedIdentityID : nil,
            authMethod: authMethod,
            useMosh: false,
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
            if authMethod == .password, passwordTouched, !password.isEmpty {
                try KeychainKeyStore().storePassword(password, hostID: host.id)
            }
            if authMethod == .key {
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
        switch authMethod {
        case .password:
            if passwordTouched, !password.isEmpty {
                return .password(password)
            }
            let existing = try KeychainKeyStore().loadPassword(hostID: host.id)
            return .password(existing)
        case .key:
            guard let identityID = selectedIdentityID else {
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
                if hostname.lowercased().hasSuffix(".ts.net") {
                    return "Couldn't reach \(hostname):\(port) — check that Tailscale is connected on this device and the peer is online"
                }
                return "Couldn't reach \(hostname):\(port) — host unreachable or blocked"
            }
            if m.contains("NIOConnectionError") || m.contains("refused") {
                return "Connection refused at \(hostname):\(port) — is SSH running on that port?"
            }
            return "Transport error: \(m)"
        case .invalidKey(let m):
            return "Key problem: \(m)"
        case .notConnected:
            return "Not connected"
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
