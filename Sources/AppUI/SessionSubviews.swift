#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

/// Progress indicator + "taking longer than usual" recovery buttons shown
/// while a session is opening or reconnecting.
struct SessionLoadingScreen: View {
    let label: String
    let showStuckRecovery: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(DS.Color.titaniumLight)
            Text(label)
                .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
            if showStuckRecovery {
                Text("Taking longer than usual…")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                HStack(spacing: DS.Spacing.md) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(DSPrimaryButtonStyle())
                    Button("Back", action: onBack)
                        .buttonStyle(DSSecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.void)
    }
}

/// Error screen shown when session open fails irrecoverably.
struct SessionErrorScreen: View {
    let error: String
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DS.Color.spark)
            Text("Couldn't open the session")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.textPrimary)
            Text(error.isEmpty ? "(no error message)" : error)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
                .textSelection(.enabled)
            HStack(spacing: DS.Spacing.md) {
                Button("Retry", action: onRetry)
                    .buttonStyle(DSPrimaryButtonStyle())
                Button("Back", action: onBack)
                    .buttonStyle(DSSecondaryButtonStyle())
            }
            .padding(.top, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.void)
    }
}

#endif
