#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

struct CopyURLPickerSheet: View {
    let urls: [DetectedURL]
    let onPick: (DetectedURL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(urls.reversed()) { detected in
                            Button {
                                onPick(detected)
                                dismiss()
                            } label: {
                                row(for: detected)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("URLs on screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for detected: DetectedURL) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detected.url.host ?? detected.raw)
                    .font(DS.Font.rowTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detected.raw)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Image(systemName: "doc.on.doc")
                .foregroundStyle(DS.Color.accent)
                .accessibilityLabel("Copy URL")
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("No URLs on screen")
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Scroll the terminal so a URL is visible, then try again.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surface0)
    }
}
#endif
