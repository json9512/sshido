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

/// Thin status bar shown above the agent bar when voice-input mode is active.
struct SessionVoiceStrip: View {
    @ObservedObject var voice: VoiceInputController

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.accent)
                .font(.system(size: 14))
            Text(status)
                .font(DS.Font.mono).lineLimit(2)
                .foregroundStyle(voice.state == .sending ? DS.Color.accent : DS.Color.textPrimary)
            Spacer()
        }
        .padding(DS.Spacing.sm).background(DS.Color.surface1)
    }

    private var icon: String {
        switch voice.state {
        case .listening:    return "waveform"
        case .translating:  return "brain"
        case .sending:      return "arrow.right.circle.fill"
        default:            return "mic.fill"
        }
    }

    private var status: String {
        switch voice.state {
        case .idle:        return ""
        case .voiceActive: return "Voice mode"
        case .listening:
            return voice.transcript.isEmpty ? "Listening…" : voice.transcript
        case .translating:
            return voice.aiStatus.isEmpty ? voice.transcript : voice.aiStatus
        case .sending:
            return voice.translatedCommand.isEmpty ? voice.transcript : voice.translatedCommand
        }
    }
}
#endif
