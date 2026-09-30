#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct HostFingerprintsView: View {
    @Environment(\.services) private var services
    @State private var entries: [KnownHost] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && entries.isEmpty {
                EmptyStateView(title: "No trusted hosts")
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink {
                            HostFingerprintDetailView(entry: entry) { Task { await remove(entry) } }
                        } label: {
                            TideRow(icon: "lock.shield", title: "\(entry.host):\(entry.port)", subtitle: entry.fingerprint, monoSubtitle: true)
                        }
                        .tideRow()
                        .swipeActions {
                            Button { Task { await remove(entry) } } label: { Label("Forget", systemImage: "trash") }
                                .tint(DS.Color.error)
                        }
                    }
                }
                .tideList()
            }
        }
        .tideScreen()
        .navigationTitle("Trusted hosts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        entries = await services.knownHosts.all()
        loaded = true
    }

    private func remove(_ entry: KnownHost) async {
        try? await services.knownHosts.remove(host: entry.host, port: entry.port)
        await reload()
    }
}

struct HostFingerprintDetailView: View {
    let entry: KnownHost
    let onForget: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                CopyableCode(text: entry.fingerprint) { toast = "Copied" }.tideRow()
            } header: {
                SectionLabel("SHA256 · \(entry.host):\(entry.port)")
            }
            Section {
                LabeledContent("First trusted", value: entry.firstSeen.formatted(date: .abbreviated, time: .shortened)).tideRow()
                LabeledContent("Last seen", value: entry.lastSeen.formatted(date: .abbreviated, time: .shortened)).tideRow()
            }
        }
        .tideList()
        .navigationTitle("Fingerprint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIcon(systemName: "trash", label: "Forget", tint: DS.Color.error) { confirmForget = true }
            }
        }
        .confirmationDialog("Forget this host?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                onForget()
                dismiss()
            }
        } message: {
            Text("The next connection asks you to verify its key again.")
        }
        .toast($toast)
    }
}
#endif
