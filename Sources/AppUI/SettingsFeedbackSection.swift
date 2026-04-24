#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

struct FeedbackSettingsSection: View {
    @Binding var toast: String?

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var entitlements = Entitlements.shared
    @State private var themeID: String = FeedbackPreferences.shared.themeID
    @State private var expanded = false

    private var active: FeedbackTheme {
        FeedbackThemes.theme(for: themeID) ?? FeedbackThemes.subtle
    }

    var body: some View {
        Section {
            activePreview
            expandToggle
            if expanded {
                themeList
            }
        } header: {
            DSSectionHeader("Agent event feedback")
        } footer: {
            Text("Fires haptics when pushes arrive in the foreground. Background pushes use the system notification sound set in iOS Settings.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .listRowBackground(DS.Color.surface1)
    }

    @ViewBuilder
    private var activePreview: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: active.isPremium ? "waveform.circle.fill" : "waveform")
                .foregroundStyle(DS.Color.accent)
                .font(.system(size: 22))
                .frame(width: 44, height: 30)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(active.name)
                    .font(DS.Font.rowTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(active.description)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var expandToggle: some View {
        Button {
            withAnimation(DS.Animation.quick) { expanded.toggle() }
        } label: {
            HStack {
                Text(expanded ? "Hide feedback themes" : "Change feedback")
                    .foregroundStyle(DS.Color.accent)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(DS.Color.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var themeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(FeedbackThemes.all.enumerated()), id: \.element.id) { idx, theme in
                themeRow(theme)
                if idx < FeedbackThemes.all.count - 1 {
                    Divider()
                        .background(DS.Color.titaniumDark.opacity(0.3))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func themeRow(_ theme: FeedbackTheme) -> some View {
        let isActive = themeID == theme.id
        let locked = theme.isPremium && !entitlements.hasPlus
        Button {
            if locked {
                router.sheet = .paywall(.plusLocked(feature: "Feedback theme \"\(theme.name)\""))
            } else {
                themeID = theme.id
                FeedbackPreferences.shared.themeID = theme.id
                toast = "Feedback: \(theme.name)"
                AgentEventFeedback.shared.fire(.needsInput)
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: theme.isPremium ? "waveform.circle.fill" : "waveform")
                    .foregroundStyle(locked ? DS.Color.textTertiary : DS.Color.accent)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 30)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(theme.name)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(theme.description)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                if isActive && !locked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.accent)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 12))
                }
            }
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
