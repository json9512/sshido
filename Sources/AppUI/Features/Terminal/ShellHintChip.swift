#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ShellHintChip: View {
    let hint: DetectedShellHint
    let onCopy: () -> Void
    let onRun: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(hint.promptInput)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "doc.on.doc", label: "Copy command", kind: .quiet, size: 36, action: onCopy)
            IconButton(systemName: "play.fill", label: "Type into prompt", kind: .primary, size: 36, action: onRun)
            IconButton(systemName: "xmark", label: "Dismiss", kind: .quiet, size: 36, action: onDismiss)
        }
        .padding(.leading, DS.Spacing.md)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Color.line, lineWidth: 1))
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }
}
#endif
