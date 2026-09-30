#if canImport(UIKit)
import SwiftUI

struct SessionLoadingScreen: View {
    let label: String
    let showStuckRecovery: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            AnimatedGlyph(animation: .connecting, size: CGSize(width: 84, height: 84))
            Text(label).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
            if showStuckRecovery {
                HStack(spacing: DS.Spacing.xl) {
                    IconButton(systemName: "chevron.left", label: "Back", action: onBack)
                    IconButton(systemName: "arrow.clockwise", label: "Retry", kind: .primary, action: onRetry)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(DS.Motion.spring, value: showStuckRecovery)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.void)
    }
}

struct SessionErrorScreen: View {
    let error: String
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            AnimatedGlyph(animation: .fail, loop: false, size: CGSize(width: 84, height: 84))
            Text(error.isEmpty ? "Couldn't open the session" : error)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
                .textSelection(.enabled)
            HStack(spacing: DS.Spacing.xl) {
                IconButton(systemName: "chevron.left", label: "Back", action: onBack)
                IconButton(systemName: "arrow.clockwise", label: "Retry", kind: .primary, action: onRetry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.void)
    }
}
#endif
