#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ShortcutGroupsListView: View {
    @State private var groups: [ShortcutGroup] = []
    @State private var editMode: EditMode = .inactive
    @State private var pendingDelete: ShortcutGroup?

    var body: some View {
        List {
            Section {
                ForEach(groups) { group in
                    NavigationLink {
                        ShortcutGroupEditorView(mode: .edit(group))
                    } label: {
                        row(for: group)
                    }
                    .dsRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = group
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    Task {
                        try? await ShortcutGroupStore.shared.moveGroup(
                            from: source, to: destination)
                        NotificationCenter.default.post(
                            name: .hotkeyLayoutChanged, object: nil)
                        await reload()
                    }
                }
            } footer: {
                Text("Groups appear on the bar above the keyboard. Tap a group there to reveal its shortcuts.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .dsFormStyle()
        .navigationTitle("Shortcut groups")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                NavigationLink {
                    ShortcutGroupEditorView(mode: .create)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
            Task { await reload() }
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \"\($0.label)\"?" } ?? "Delete group?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { group in
            Button("Delete \(group.shortcuts.count) shortcut(s)", role: .destructive) {
                Task { await delete(group) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("This removes the group and its \(group.shortcuts.count) shortcut(s).")
        }
    }

    @ViewBuilder
    private func row(for group: ShortcutGroup) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: group.sfSymbol ?? "square.grid.2x2")
                .font(.system(size: 16))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(group.label)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle(for: group))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func subtitle(for group: ShortcutGroup) -> String {
        let n = group.shortcuts.count
        let word = n == 1 ? "shortcut" : "shortcuts"
        if n == 0 { return "Empty" }
        let preview = group.shortcuts.prefix(3).map(\.label).joined(separator: " · ")
        return "\(n) \(word) — \(preview)"
    }

    private func reload() async {
        groups = await ShortcutGroupStore.shared.groups
    }

    private func delete(_ group: ShortcutGroup) async {
        pendingDelete = nil
        try? await ShortcutGroupStore.shared.removeGroup(id: group.id)
        NotificationCenter.default.post(name: .hotkeyLayoutChanged, object: nil)
        await reload()
    }
}
#endif
