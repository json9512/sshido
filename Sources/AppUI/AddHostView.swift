#if canImport(UIKit)
import SwiftUI
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
    @State private var tmuxSession = "sshido"
    @State private var forceCompactAgent = true
    @State private var showAddIdentity = false
    @State private var showAdvanced = false
    @State private var error: String?

    init(existing: RemoteHost? = nil, onSaved: @escaping (RemoteHost) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).autocorrectionDisabled()
                    TextField("Host", text: $hostname)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Different networks? Install Tailscale on both devices, then use the Tailscale hostname (e.g. mac.tail-scale.ts.net) as Host.")
                }
                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        Text("Key").tag(HostAuthMethod.key)
                        Text("Password").tag(HostAuthMethod.password)
                    }
                    .pickerStyle(.segmented)
                    if authMethod == .key {
                        Picker("Key", selection: $selectedIdentityID) {
                            Text("— none —").tag(Optional<UUID>.none)
                            ForEach(identities) { id in
                                Text(id.label).tag(Optional(id.id))
                            }
                        }
                        Button("Add new key…") { showAddIdentity = true }
                    } else {
                        SecureField(existing != nil ? "Password (unchanged if blank)" : "Password",
                                    text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: password) { _, _ in passwordTouched = true }
                    }
                }
                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        TextField("tmux session", text: $tmuxSession)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Force compact agent UI", isOn: $forceCompactAgent)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(existing == nil ? "Add server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid)
                }
            }
            .task {
                identities = await IdentityStore.shared.all()
                hydrateFromExisting()
            }
            .sheet(isPresented: $showAddIdentity) {
                AddIdentityView { added in
                    identities.append(added)
                    selectedIdentityID = added.id
                }
            }
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
        tmuxSession = h.tmuxSession
        forceCompactAgent = h.forceCompactAgent
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
        let hostID = existing?.id ?? UUID()
        let host = RemoteHost(
            id: hostID,
            name: name,
            hostname: hostname,
            port: Int(port) ?? 22,
            username: username,
            identityID: authMethod == .key ? selectedIdentityID : nil,
            authMethod: authMethod,
            useMosh: false,
            useTmux: true,
            tmuxSession: tmuxSession,
            agentProfileID: nil,
            forceCompactAgent: forceCompactAgent
        )
        do {
            if authMethod == .password, passwordTouched, !password.isEmpty {
                try KeychainKeyStore().storePassword(password, hostID: host.id)
            }
            if authMethod == .key {
                KeychainKeyStore().deletePassword(hostID: host.id)
            }
            try await HostStore.shared.upsert(host)
            onSaved(host)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif
