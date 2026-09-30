#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

struct CopyURLPickerSheet: View {
    let urls: [DetectedURL]
    let onPick: (DetectedURL) -> Void
    let onOpen: (DetectedURL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    EmptyStateView(title: "No links on screen")
                } else {
                    List {
                        ForEach(urls.reversed()) { detected in
                            row(detected).tideRow()
                        }
                    }
                    .tideList()
                }
            }
            .tideScreen()
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .sheetActions(cancel: { dismiss() })
        }
    }

    private func row(_ detected: DetectedURL) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.xs) {
                    if OAuthURLDetector.detect(detected.raw) != nil {
                        Image(systemName: "lock.shield").font(.system(size: 12)).foregroundStyle(DS.Color.accent)
                            .accessibilityLabel("Sign-in link")
                    }
                    Text(detected.url.host ?? detected.raw).font(DS.Font.rowTitle).lineLimit(1).truncationMode(.middle)
                }
                Text(detected.raw).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "doc.on.doc", label: "Copy link", kind: .quiet, size: 40) {
                onPick(detected)
                dismiss()
            }
            IconButton(systemName: "safari", label: "Open", size: 40) {
                onOpen(detected)
                dismiss()
            }
        }
    }
}
#endif
