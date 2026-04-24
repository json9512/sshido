#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ShortcutGroupEditorView: View {
    enum Mode {
        case create
        case edit(ShortcutGroup)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var draft: ShortcutGroup
    @State private var persisted: Bool
    @State private var shortcutsEditMode: EditMode = .inactive
    @State private var pendingDelete: CustomShortcut?
    @State private var saveError: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            self._draft = State(initialValue: ShortcutGroup(label: ""))
            self._persisted = State(initialValue: false)
        case .edit(let g):
            self._draft = State(initialValue: g)
            self._persisted = State(initialValue: true)
        }
    }

    var body: some View {
        Form {
            Section(header: DSSectionHeader("Name")) {
                TextField("Group name", text: $draft.label)
                    .font(DS.Font.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .dsRow()
            }

            Section(header: DSSectionHeader("Icon")) {
                iconPicker
                    .dsRow()
            }

            Section {
                if draft.shortcuts.isEmpty {
                    Text("No shortcuts yet. Tap + to add one.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .dsRow()
                } else {
                    ForEach(draft.shortcuts) { sc in
                        NavigationLink {
                            ShortcutEditorView(groupId: draft.id, mode: .edit(sc)) {
                                Task { await refreshFromStore() }
                            }
                        } label: {
                            shortcutRow(sc)
                        }
                        .dsRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = sc
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        draft.shortcuts.move(fromOffsets: source, toOffset: destination)
                        if persisted {
                            Task {
                                try? await ShortcutGroupStore.shared.moveShortcut(
                                    inGroup: draft.id, from: source, to: destination)
                                NotificationCenter.default.post(
                                    name: .hotkeyLayoutChanged, object: nil)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    DSSectionHeader("Shortcuts")
                    Spacer()
                    if !draft.shortcuts.isEmpty {
                        Button(shortcutsEditMode.isEditing ? "Done" : "Reorder") {
                            withAnimation {
                                shortcutsEditMode = shortcutsEditMode.isEditing ? .inactive : .active
                            }
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.accent)
                    }
                }
            }

            if let saveError {
                Section { InlineErrorText(saveError) }
            }
        }
        .dsFormStyle()
        .navigationTitle(persisted ? "Edit group" : "New group")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $shortcutsEditMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if persisted {
                    NavigationLink {
                        ShortcutEditorView(groupId: draft.id, mode: .create) {
                            Task { await refreshFromStore() }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onChange(of: draft.label) { _, _ in
            guard persisted, canSave else { return }
            Task { await persistGroupMetadata() }
        }
        .onChange(of: draft.sfSymbol) { _, _ in
            guard persisted else { return }
            Task { await persistGroupMetadata() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
            guard persisted else { return }
            Task { await refreshFromStore() }
        }
        .confirmationDialog(
            "Delete shortcut?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { sc in
            Button("Delete \"\(sc.label)\"", role: .destructive) {
                Task { await deleteShortcut(sc) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var iconPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            iconChip(nil)
            ForEach(GroupIconCatalog.symbols, id: \.self) { sym in
                iconChip(sym)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func iconChip(_ symbol: String?) -> some View {
        let selected = draft.sfSymbol == symbol
        Button {
            draft.sfSymbol = symbol
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 17))
                } else {
                    Image(systemName: "slash.circle").font(.system(size: 17))
                }
            }
            .frame(width: 40, height: 40)
            .foregroundStyle(selected ? DS.Color.textOnAccent : DS.Color.textPrimary)
            .background(
                selected ? DS.Color.accent : DS.Color.surface2,
                in: RoundedRectangle(cornerRadius: DS.Radius.md)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shortcutRow(_ sc: CustomShortcut) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Text(sc.label)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.sm)
            Text(ShortcutDisplay.display(sc.bytes))
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var canSave: Bool {
        !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        saveError = nil
        let trimmed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.label = trimmed
        do {
            try await ShortcutGroupStore.shared.addGroup(draft)
            persisted = true
            NotificationCenter.default.post(name: .hotkeyLayoutChanged, object: nil)
            dismiss()
        } catch {
            saveError = "Couldn't save group: \(error.localizedDescription)"
        }
    }

    private func persistGroupMetadata() async {
        let trimmed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = draft
        copy.label = trimmed
        try? await ShortcutGroupStore.shared.updateGroup(copy)
        NotificationCenter.default.post(name: .hotkeyLayoutChanged, object: nil)
    }

    private func refreshFromStore() async {
        let groups = await ShortcutGroupStore.shared.groups
        if let fresh = groups.first(where: { $0.id == draft.id }) {
            draft = fresh
        }
    }

    private func deleteShortcut(_ sc: CustomShortcut) async {
        pendingDelete = nil
        draft.shortcuts.removeAll { $0.id == sc.id }
        if persisted {
            try? await ShortcutGroupStore.shared.removeShortcut(
                fromGroup: draft.id, shortcutId: sc.id)
            NotificationCenter.default.post(name: .hotkeyLayoutChanged, object: nil)
        }
    }
}
#endif
