#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ServersSettingsView: View {
    @Environment(\.services) private var services
    @State private var knownHosts = 0
    @AppStorage(MetricsSettings.intervalKey) private var metricsInterval: Int = MetricsSettings.defaultIntervalSeconds

    var body: some View {
        List {
            KeysSection()
            Section {
                NavigationLink { HostFingerprintsView() } label: {
                    TideRow(icon: "lock.shield", title: "Trusted hosts", subtitle: "\(knownHosts) fingerprints")
                }
                .tideRow()
            }
            Section {
                Picker(selection: $metricsInterval) {
                    ForEach(MetricsSettings.allowedIntervals, id: \.self) { Text("\($0) s").tag($0) }
                } label: {
                    TideRow(icon: "gauge.with.dots.needle.33percent", title: "Metrics interval")
                }
                .tideRow()
            }
        }
        .tideList()
        .navigationTitle("Servers & keys")
        .navigationBarTitleDisplayMode(.inline)
        .task { knownHosts = await services.knownHosts.all().count }
    }
}

struct KeysSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List { KeysSection() }
                .tideList()
                .navigationTitle("Keys")
                .navigationBarTitleDisplayMode(.inline)
                .sheetActions(cancel: { dismiss() })
        }
    }
}

struct KeysSection: View {
    @Environment(\.services) private var services
    @State private var identities: [Identity] = []
    @State private var usage: [UUID: [RemoteHost]] = [:]
    @State private var pendingDelete: Identity?
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(identities) { identity in
                let users = usage[identity.id] ?? []
                TideRow(icon: "key.horizontal", title: identity.label,
                        subtitle: users.isEmpty ? "Unused" : users.map(\.name).joined(separator: ", "),
                        tint: users.isEmpty ? DS.Color.textTertiary : DS.Color.accent)
                    .tideRow()
                    .swipeActions {
                        Button { pendingDelete = identity } label: { Label("Delete", systemImage: "trash") }
                            .tint(DS.Color.error)
                    }
            }
            Button { adding = true } label: {
                TideRow(icon: "plus.circle.fill", title: "Add key")
            }
            .tideRow()
            .task { await reload() }
            .sheet(isPresented: $adding, onDismiss: { Task { await reload() } }) {
                AddIdentityView { _ in }
            }
            .confirmationDialog(pendingDelete.map { "Delete \($0.label)?" } ?? "", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { identity in
                Button("Delete key", role: .destructive) { Task { await delete(identity) } }
            } message: { identity in
                Text(deleteMessage(identity))
            }
            if let error { InlineErrorText(error).tideRow() }
        } header: {
            SectionLabel("Keys")
        }
    }

    private func deleteMessage(_ identity: Identity) -> String {
        let users = usage[identity.id] ?? []
        guard !users.isEmpty else { return "The private key is removed from this device's Keychain." }
        return "\(users.map(\.name).joined(separator: ", ")) will need another key."
    }

    private func reload() async {
        identities = await services.identities.all()
        let hosts = await services.hosts.all()
        let pairs = hosts.compactMap { host in host.identityID.map { ($0, host) } }
        usage = Dictionary(grouping: pairs, by: \.0).mapValues { $0.map(\.1) }
    }

    private func delete(_ identity: Identity) async {
        do {
            try await services.identities.remove(id: identity.id)
            error = nil
        } catch {
            self.error = "Could not delete the key: \(error.localizedDescription)"
        }
        pendingDelete = nil
        await reload()
    }
}
#endif
