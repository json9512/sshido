#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct SessionInfoSheet: View {
    let session: Session
    let host: RemoteHost
    let connected: Bool
    let rename: (String) async throws -> Session

    @State private var name: String
    @State private var current: Session
    @State private var saving = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        session: Session,
        host: RemoteHost,
        connected: Bool,
        rename: @escaping (String) async throws -> Session
    ) {
        self.session = session
        self.host = host
        self.connected = connected
        self.rename = rename
        self._name = State(initialValue: session.displayName(on: host))
        self._current = State(initialValue: session)
    }

    private var displayName: String { current.displayName(on: host) }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != displayName && !saving
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: DSSectionHeader("Name")) {
                    TextField("Session name", text: $name)
                        .focused($nameFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { save() }
                        .disabled(saving)
                        .dsRow()
                    if host.useTmux {
                        Text("Renames the tmux session on \(host.name). tmux replaces \".\" and \":\" with \"_\".")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                            .dsRow()
                    }
                }
                Section(header: DSSectionHeader("Session")) {
                    infoRow("Host", "\(host.username)@\(host.hostname):\(host.port)")
                    infoRow("Status", connected ? "Connected" : "Not connected")
                    infoRow("Opened", current.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if host.useTmux {
                        infoRow("tmux session", displayName, mono: true)
                        infoRow("tmux id", current.tmuxSessionID ?? "not resolved yet", mono: true)
                    } else {
                        infoRow("tmux", "Disabled for this host")
                    }
                    infoRow("Session ref", String(current.id.uuidString.prefix(8)), mono: true)
                }
                if let error {
                    Section { InlineErrorText(error) }
                }
            }
            .dsFormStyle()
            .navigationTitle("Session info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.md)
            Text(value)
                .font(mono ? DS.Font.monoSmall : DS.Font.caption)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .dsRow()
    }

    private func save() {
        guard canSave else { return }
        nameFocused = false
        saving = true
        error = nil
        Task {
            do {
                current = try await rename(trimmed)
                // tmux may have rewritten it; show what the server settled on.
                name = current.displayName(on: host)
            } catch {
                self.error = error.localizedDescription
                name = current.displayName(on: host)
            }
            saving = false
        }
    }
}
#endif
