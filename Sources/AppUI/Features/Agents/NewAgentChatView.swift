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
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                TextField("What is it about?", text: $title)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { create() }
                    .frame(minHeight: DS.hitTarget)
                    .tideRow()
            }
            if case .failed(let reason) = agents.creation {
                Section { InlineErrorText(reason).tideRow() }
            }
        }
        .tideList()
        .navigationTitle("New chat")
        .toolbarTitleDisplayMode(.inline)
        .sheetActions(cancel: { dismiss() }, confirm: create, confirmEnabled: !trimmed.isEmpty, working: creating)
        .interactiveDismissDisabled(creating)
        .task {
            agents.resetCreation()
            focused = true
        }
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

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmed.isEmpty else { return }
        Task { await agents.createChat(.createChat(title: trimmed)) }
    }
}
#endif
