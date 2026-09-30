#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct NewAgentChatView: View {
    let kind: AgentChatKind
    let onCreated: (String) -> Void

    @ObservedObject private var agents = AgentModeController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var members: [MemberDraft] = []
    @State private var turnCap = 6

    struct MemberDraft: Identifiable, Equatable {
        let id: UUID
        let name: String
        let harness: AgentHarness
        let model: String

        func with(name: String? = nil, harness: AgentHarness? = nil, model: String? = nil) -> MemberDraft {
            MemberDraft(id: id, name: name ?? self.name, harness: harness ?? self.harness, model: model ?? self.model)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField(kind == .group ? "e.g. Haiku workshop" : "e.g. Fix the login bug", text: $title)
                    .dsRow()
            } header: {
                DSSectionHeader("Title")
            }
            if kind == .group { memberSection; turnSection }
            if case .failed(let reason) = agents.creation {
                Section {
                    Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.error).dsRow()
                }
            } else if let problem, !trimmedTitle.isEmpty {
                Section {
                    Text(problem).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).dsRow()
                }
            }
        }
        .dsFormStyle()
        .navigationTitle(kind == .group ? "New group chat" : "New chat")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if creating {
                    ProgressView().accessibilityLabel("Creating chat")
                } else {
                    Button("Create") { Task { await create() } }.disabled(problem != nil)
                }
            }
        }
        .interactiveDismissDisabled(creating)
        .task {
            agents.resetCreation()
            members = [
                newMember,
                newMember,
            ]
        }
        .onChange(of: agents.creation) { _, state in
            guard case .created(let id) = state else { return }
            agents.resetCreation()
            onCreated(id)
        }
    }

    private var newMember: MemberDraft {
        MemberDraft(id: UUID(), name: "", harness: agents.settings.worker, model: agents.settings.workerModel)
    }

    private var creating: Bool {
        if case .waiting = agents.creation { return true }
        return false
    }

    private var memberSection: some View {
        Section {
            ForEach(members) { member in
                MemberEditor(member: member, removable: members.count > 2) { next in
                    members = members.map { $0.id == next.id ? next : $0 }
                } onRemove: {
                    members = members.filter { $0.id != member.id }
                }
                .dsRow()
            }
            Button {
                members = members + [newMember]
            } label: {
                Label("Add member", systemImage: "plus.circle").font(DS.Font.rowTitle)
            }
            .disabled(members.count >= 12)
            .dsRow()
        } header: {
            DSSectionHeader("Members")
        } footer: {
            Text("Each member runs in its own container. After each of your messages, the picker model (\(agents.settings.pickerModel.isEmpty ? "not set" : agents.settings.pickerModel)) chooses who speaks next, one at a time, until it hands the chat back to you.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var turnSection: some View {
        Section {
            Stepper(value: $turnCap, in: 1...50) {
                Text("Up to \(turnCap) replies per message").font(DS.Font.rowTitle)
            }
            .dsRow()
        } header: {
            DSSectionHeader("Turn limit")
        } footer: {
            Text("A hard stop, so members can't keep talking forever.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var problem: String? {
        if trimmedTitle.isEmpty { return "Give the chat a title." }
        guard kind == .group else { return nil }
        if agents.settings.pickerModel.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Set a picker model in Settings → Agent mode first."
        }
        let names = members.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if names.contains("") { return "Every member needs a name." }
        if Set(names).count != names.count { return "Member names must differ." }
        if members.contains(where: { $0.harness == .local && $0.model.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Local-model members need a model name."
        }
        return nil
    }

    private func create() async {
        guard problem == nil else { return }
        guard kind == .group else {
            await agents.createChat(.createChat(title: trimmedTitle))
            return
        }
        let specs = members.map { m in
            let model = m.model.trimmingCharacters(in: .whitespaces)
            return AgentMemberSpec(name: m.name.trimmingCharacters(in: .whitespacesAndNewlines), harness: m.harness,
                                   model: model.isEmpty ? nil : model)
        }
        await agents.createChat(.createGroup(title: trimmedTitle, members: specs, turnCap: turnCap))
    }
}

private struct MemberEditor: View {
    let member: NewAgentChatView.MemberDraft
    let removable: Bool
    let onChange: (NewAgentChatView.MemberDraft) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                TextField("Name, e.g. critic", text: Binding(get: { member.name }, set: { onChange(member.with(name: $0)) }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(DS.Font.rowTitle)
                if removable {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill").foregroundStyle(DS.Color.error)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(member.name.isEmpty ? "member" : member.name)")
                }
            }
            Picker("Harness", selection: Binding(get: { member.harness }, set: { onChange(member.with(harness: $0)) })) {
                ForEach(AgentHarness.allCases) { h in Text(h.label).tag(h) }
            }
            .font(DS.Font.body)
            TextField(member.harness == .local ? "Model name (required)" : "Model (optional)",
                      text: Binding(get: { member.model }, set: { onChange(member.with(model: $0)) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(DS.Font.body)
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
#endif
