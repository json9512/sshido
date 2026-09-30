#if canImport(UIKit)
import SwiftUI

struct GuideStep: Identifiable {
    let icon: String
    let title: String
    let text: String
    let code: String?

    var id: String { title }
}

struct GuideView: View {
    let title: String
    let steps: [GuideStep]
    var link: (label: String, url: String)?
    @State private var toast: String?

    var body: some View {
        List {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                Section {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        HStack(spacing: DS.Spacing.md) {
                            Text("\(index + 1)")
                                .font(DS.Font.mono(13, .semibold))
                                .foregroundStyle(DS.Color.textOnAccent)
                                .frame(width: 26, height: 26)
                                .background(DS.Color.accent, in: Circle())
                            Image(systemName: step.icon).foregroundStyle(DS.Color.accent)
                            Text(step.title).font(DS.Font.headline)
                        }
                        Text(step.text).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let code = step.code {
                            CopyableCode(text: code) { toast = "Copied" }
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                    .tideRow()
                }
            }
            if let link, let url = URL(string: link.url) {
                Section {
                    Link(destination: url) {
                        TideRow(icon: "arrow.up.right.square", title: link.label) {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                    .tideRow()
                }
            }
        }
        .tideList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }
}
#endif
