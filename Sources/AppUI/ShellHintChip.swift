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
        HStack(spacing: DS.Spacing.sm) {
            Text(hint.promptInput)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Copy command")
            Button(action: onRun) {
                Label("Run", systemImage: "play.fill")
                    .font(DS.Font.captionMedium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityHint("Types the command into the prompt without pressing Return")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, DS.Spacing.md)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg).stroke(DS.Color.titaniumDark, lineWidth: 0.5))
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }
}
#endif
