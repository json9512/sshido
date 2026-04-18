#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ManageKeysView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var identities: [Identity] = []
    @State private var hostsByIdentity: [UUID: [RemoteHost]] = [:]
    @State private var pendingDelete: Identity?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if identities.isEmpty {
                    Section {
                        Text("No keys saved.")
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                } else {
                    Section {
                        ForEach(identities) { id in
                            row(for: id).dsRow()
                        }
                        .onDelete { offsets in
                            guard let idx = offsets.first else { return }
                            pendingDelete = identities[idx]
                        }
                    } footer: {
                        Text("Deleting a key removes its private key from the Keychain on this device. Any servers still authorized with the public key will remain authorized until you remove it server-side.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                if let error {
                    Section { InlineErrorText(error) }
                }
            }
            .dsFormStyle()
            .navigationTitle("Manage keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { target in
                Button("Delete key", role: .destructive) {
                    Task { await delete(target) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { target in
                Text(confirmationMessage(for: target))
            }
        }
    }

    @ViewBuilder
    private func row(for id: Identity) -> some View {
        let usedBy = hostsByIdentity[id.id] ?? []
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(id.label).font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
            if usedBy.isEmpty {
                Text("Not used by any server")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                Text("Used by \(usedBy.count) server\(usedBy.count == 1 ? "" : "s"): \(usedBy.map(\.name).joined(separator: ", "))")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var confirmationTitle: String {
        guard let pendingDelete else { return "Delete key" }
        return "Delete \(pendingDelete.label)?"
    }

    private func confirmationMessage(for id: Identity) -> String {
        let usedBy = hostsByIdentity[id.id] ?? []
        if usedBy.isEmpty {
            return "This removes the private key from the Keychain. This cannot be undone."
        }
        let names = usedBy.map(\.name).joined(separator: ", ")
        return "Used by \(names). Those servers will fall back to asking for a new key on next connect."
    }

    private func reload() async {
        identities = await IdentityStore.shared.all()
        let allHosts = await HostStore.shared.all()
        var map: [UUID: [RemoteHost]] = [:]
        for host in allHosts {
            if let iid = host.identityID {
                map[iid, default: []].append(host)
            }
        }
        hostsByIdentity = map
    }

    private func delete(_ id: Identity) async {
        error = nil
        do {
            try await IdentityStore.shared.remove(id: id.id)
            pendingDelete = nil
            await reload()
        } catch {
            self.error = "Delete failed: \(error)"
            pendingDelete = nil
        }
    }
}
#endif
