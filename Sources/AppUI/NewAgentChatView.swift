#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct NewAgentChatView: View {
    let onCreated: (String) -> Void

    @ObservedObject private var agents = AgentModeController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        Form {
            Section {
                TextField("e.g. Fix the login bug", text: $title)
                    .dsRow()
            } header: {
                DSSectionHeader("Title")
            } footer: {
                Text("You talk to an orchestrator. It works out what you need, starts subagents when the work calls for them, checks their work, and reports back here.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            if case .failed(let reason) = agents.creation {
                Section {
                    Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.error).dsRow()
                }
            }
        }
        .dsFormStyle()
        .navigationTitle("New chat")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if creating {
                    ProgressView().accessibilityLabel("Creating chat")
                } else {
                    Button("Create") { Task { await agents.createChat(.createChat(title: trimmedTitle)) } }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(creating)
        .task { agents.resetCreation() }
        .onChange(of: agents.creation) { _, state in
            guard case .created(let id) = state else { return }
            agents.resetCreation()
            onCreated(id)
        }
    }

    private var creating: Bool {
        if case .waiting = agents.creation { return true }
        return false
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
