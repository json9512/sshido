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
    @Environment(\.dismiss) private var dismiss

    init(session: Session, host: RemoteHost, connected: Bool, rename: @escaping (String) async throws -> Session) {
        self.session = session
        self.host = host
        self.connected = connected
        self.rename = rename
        self._name = State(initialValue: session.displayName(on: host))
        self._current = State(initialValue: session)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != current.displayName(on: host) && !saving }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                        .disabled(saving)
                        .frame(minHeight: DS.hitTarget)
                        .tideRow()
                }
                Section {
                    info("Server", "\(host.username)@\(host.hostname):\(host.port)", mono: true)
                    info("Status", connected ? "Connected" : "Not connected")
                    info("Opened", current.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if host.useTmux {
                        info("tmux", current.tmuxSessionID ?? "–", mono: true)
                    }
                    info("Ref", String(current.id.uuidString.prefix(8)), mono: true)
                }
                if let error {
                    Section { InlineErrorText(error).tideRow() }
                }
            }
            .tideList()
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .sheetActions(cancel: { dismiss() }, confirm: { Task { await save() } }, confirmEnabled: canSave, working: saving)
        }
    }

    private func info(_ label: String, _ value: String, mono: Bool = false) -> some View {
        LabeledContent {
            Text(value).font(mono ? DS.Font.monoSmall : DS.Font.callout).textSelection(.enabled)
        } label: {
            Text(label).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
        }
        .tideRow()
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        error = nil
        do {
            current = try await rename(trimmed)
        } catch {
            self.error = error.localizedDescription
        }
        name = current.displayName(on: host)
        saving = false
    }
}
#endif
