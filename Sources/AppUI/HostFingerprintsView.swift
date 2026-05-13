#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

/// Settings → Identity → Host fingerprints.
///
/// Lists every host whose key has been trusted via TOFU. Swipe to
/// remove an entry — the next connect to that host will re-prompt
/// as if it were first-seen.
public struct HostFingerprintsView: View {
    @State private var entries: [KnownHost] = []
    @State private var loaded = false

    public init() {}

    public var body: some View {
        List {
            if loaded && entries.isEmpty {
                Section {
                    Text("No hosts trusted yet. Fingerprints land here once you connect to a host and tap Trust & Connect on the verification prompt.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            HostFingerprintDetailView(entry: entry, onDelete: { remove(entry) })
                        } label: {
                            row(entry)
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { entries[$0] }
                        for entry in targets { remove(entry) }
                    }
                } footer: {
                    Text("Removing a host clears its stored fingerprint. The next connect will prompt for verification again.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
        .navigationTitle("Host fingerprints")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            loaded = true
        }
    }

    private func row(_ entry: KnownHost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.host):\(entry.port)")
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text(entry.fingerprint)
                .font(DS.Font.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        let loaded = await KnownHostStore.shared.all()
        await MainActor.run { entries = loaded }
    }

    private func remove(_ entry: KnownHost) {
        Task {
            try? await KnownHostStore.shared.remove(host: entry.host, port: entry.port)
            await reload()
        }
    }
}

struct HostFingerprintDetailView: View {
    let entry: KnownHost
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Host") {
                LabeledContent("Hostname") { Text("\(entry.host):\(entry.port)").font(DS.Font.mono) }
            }
            Section("Fingerprint (SHA256)") {
                HStack {
                    Text(entry.fingerprint)
                        .font(DS.Font.mono)
                        .textSelection(.enabled)
                    Spacer(minLength: DS.Spacing.sm)
                    Button {
                        UIPasteboard.general.string = entry.fingerprint
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(DS.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("History") {
                LabeledContent("First trusted") { Text(entry.firstSeen.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Last seen")     { Text(entry.lastSeen.formatted(date: .abbreviated, time: .shortened)) }
            }
            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Remove trust")
                }
            } footer: {
                Text("Next connect to this host will prompt for re-verification.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .navigationTitle("Fingerprint")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove trust?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onDelete()
                dismiss()
            }
        }
    }
}
#endif
