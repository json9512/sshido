#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ShortcutEditorView: View {
    enum Mode {
        case create
        case edit(CustomShortcut)
    }

    let groupId: UUID
    let mode: Mode
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var tokens: [Token]
    @State private var textDraft: String = ""
    @State private var hexDraft: String = ""
    @State private var tokensEditMode: EditMode = .inactive
    @State private var saveError: String?

    private let shortcutId: UUID

    init(groupId: UUID, mode: Mode, onChange: @escaping () -> Void = {}) {
        self.groupId = groupId
        self.mode = mode
        self.onChange = onChange
        switch mode {
        case .create:
            self._label = State(initialValue: "")
            self._tokens = State(initialValue: [])
            self.shortcutId = UUID()
        case .edit(let sc):
            self._label = State(initialValue: sc.label)
            self._tokens = State(initialValue: Token.decompose(sc.bytes))
            self.shortcutId = sc.id
        }
    }

    var body: some View {
        Form {
            labelSection
            bodySection
            textInsertSection
            keyInsertSection
            hexInsertSection
            previewSection
            if let saveError {
                Section { InlineErrorText(saveError) }
            }
        }
        .tideList()
        .navigationTitle(isEditing ? "Edit shortcut" : "New shortcut")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $tokensEditMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIcon(systemName: "checkmark", label: "Save", tint: canSave ? DS.Color.accent : DS.Color.textTertiary) {
                    Task { await save() }
                }
                .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var labelSection: some View {
        Section(header: SectionLabel("Label")) {
            TextField("e.g. Split vertical", text: $label)
                .font(DS.Font.body)
                .submitLabel(.done)
                .tideRow()
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        Section {
            if tokens.isEmpty {
                Text("Empty. Add text, a special key, or a raw byte below.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .tideRow()
            } else {
                ForEach(tokens) { token in
                    tokenRow(token)
                        .tideRow()
                }
                .onMove { source, destination in
                    tokens.move(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            bodyHeader
        }
    }

    @ViewBuilder
    private var bodyHeader: some View {
        HStack {
            SectionLabel("Body")
            Spacer()
            if tokens.count > 1 {
                Button(tokensEditMode.isEditing ? "Done" : "Reorder") {
                    withAnimation {
                        tokensEditMode = tokensEditMode.isEditing ? .inactive : .active
                    }
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.accent)
            }
        }
    }

    @ViewBuilder
    private func tokenRow(_ token: Token) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: token.symbol)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.display)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(token.kindLabel)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
            if !tokensEditMode.isEditing {
                Button {
                    tokens.removeAll { $0.id == token.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.error)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var textInsertSection: some View {
        Section(header: SectionLabel("Insert text")) {
            HStack(spacing: DS.Spacing.sm) {
                TextField("type here…", text: $textDraft)
                    .font(DS.Font.monoBody)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { addText() }
                IconButton(systemName: "plus", label: "Add text", kind: .primary, size: 36) { addText() }
                    .disabled(textDraft.isEmpty)
            }
            .tideRow()
        }
    }

    @ViewBuilder
    private var keyInsertSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                ForEach(CommonShortcuts.presets, id: \.label) { preset in
                    Button { tokens.append(.key(preset)) } label: {
                        Text(preset.label)
                            .font(DS.Font.mono(14, .medium))
                            .foregroundStyle(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .tideRow()
        } header: {
            SectionLabel("Insert special key")
        }
    }

    @ViewBuilder
    private var hexInsertSection: some View {
        Section {
            HStack(spacing: DS.Spacing.sm) {
                TextField("0x1b, 1b, or 27", text: $hexDraft)
                    .font(DS.Font.monoBody)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .onSubmit { addHex() }
                IconButton(systemName: "plus", label: "Add byte", kind: .primary, size: 36) { addHex() }
                    .disabled(ShortcutDisplay.parseByte(hexDraft) == nil)
            }
            .tideRow()
        } header: {
            SectionLabel("Insert raw byte")
        } footer: {
            Text("Hex 0x1b or decimal 27")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section(header: SectionLabel("Preview")) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(previewHuman.isEmpty ? "—" : previewHuman)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(previewHex.isEmpty ? "—" : previewHex)
                    .font(DS.Font.monoBody)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
            }
            .tideRow()
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tokens.isEmpty
    }

    private var flattenedBytes: [UInt8] {
        var out: [UInt8] = []
        for t in tokens {
            switch t {
            case .text(_, let s):    out.append(contentsOf: Array(s.utf8))
            case .key(let preset):   out.append(contentsOf: preset.bytes)
            case .rawByte(_, let b): out.append(b)
            }
        }
        return out
    }

    private var previewHuman: String {
        tokens.map(\.display).joined(separator: " ")
    }

    private var previewHex: String {
        let bytes = flattenedBytes
        guard !bytes.isEmpty else { return "" }
        return bytes.map { String(format: "\\x%02x", $0) }.joined()
    }

    private func addText() {
        let s = textDraft
        guard !s.isEmpty else { return }
        tokens.append(.text(s))
        textDraft = ""
    }

    private func addHex() {
        guard let byte = ShortcutDisplay.parseByte(hexDraft) else { return }
        tokens.append(.rawByte(byte))
        hexDraft = ""
    }

    private func save() async {
        saveError = nil
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let sc = CustomShortcut(id: shortcutId, label: trimmedLabel, bytes: flattenedBytes)
        do {
            if isEditing {
                try await ShortcutGroupStore.shared.updateShortcut(inGroup: groupId, sc)
            } else {
                try await ShortcutGroupStore.shared.addShortcut(toGroup: groupId, sc)
            }
            NotificationCenter.default.post(name: .hotkeyLayoutChanged, object: nil)
            onChange()
            dismiss()
        } catch {
            saveError = "Couldn't save shortcut: \(error.localizedDescription)"
        }
    }
}

private extension ShortcutEditorView {
    enum Token: Identifiable, Hashable {
        case text(UUID, String)
        case key(CustomShortcut)
        case rawByte(UUID, UInt8)

        static func text(_ s: String) -> Token { .text(UUID(), s) }
        static func rawByte(_ b: UInt8) -> Token { .rawByte(UUID(), b) }

        var id: String {
            switch self {
            case .text(let u, _):    return "t:\(u.uuidString)"
            case .key(let sc):       return "k:\(sc.id.uuidString)"
            case .rawByte(let u, _): return "r:\(u.uuidString)"
            }
        }

        var display: String {
            switch self {
            case .text(_, let s):    return "\"\(s)\""
            case .key(let sc):       return sc.label
            case .rawByte(_, let b): return String(format: "\\x%02x", b)
            }
        }

        var kindLabel: String {
            switch self {
            case .text:    return "text"
            case .key:     return "key"
            case .rawByte: return "raw byte"
            }
        }

        var symbol: String {
            switch self {
            case .text:    return "textformat"
            case .key:     return "keyboard"
            case .rawByte: return "number"
            }
        }

        static func decompose(_ bytes: [UInt8]) -> [Token] {
            var result: [Token] = []
            var textRun: [UInt8] = []
            func flushText() {
                guard !textRun.isEmpty else { return }
                if let s = String(bytes: textRun, encoding: .utf8) {
                    result.append(.text(s))
                } else {
                    for b in textRun { result.append(.rawByte(b)) }
                }
                textRun.removeAll()
            }
            var i = 0
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0x20 && b != 0x7f {
                    textRun.append(b)
                    i += 1
                } else {
                    flushText()
                    result.append(.rawByte(b))
                    i += 1
                }
            }
            flushText()
            return result
        }
    }
}
#endif
