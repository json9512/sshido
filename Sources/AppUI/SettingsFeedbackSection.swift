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

    var body: some View {
        Section {
            ForEach(FeedbackThemes.all) { theme in
                themeRow(theme)
            }
        } header: {
            DSSectionHeader("Agent event feedback")
        } footer: {
            Text("Fires haptics when pushes arrive in the foreground. Background pushes use the system notification sound set in iOS Settings.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
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
                // Play a preview haptic so the user can feel what they picked.
                AgentEventFeedback.shared.fire(.needsInput)
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: theme.isPremium ? "waveform.circle.fill" : "waveform")
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(theme.name)
                        .font(DS.Font.rowTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(theme.isPremium ? "sshido+" : "Free")
                        .font(DS.Font.caption)
                        .foregroundStyle(theme.isPremium ? DS.Color.accent : DS.Color.textTertiary)
                }
                Spacer()
                if isActive && !locked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.accent)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .dsRow()
    }
}
#endif
