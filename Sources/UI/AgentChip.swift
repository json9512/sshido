#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif

public struct AgentChip: View {
    let profile: AgentProfile
    public init(profile: AgentProfile) { self.profile = profile }
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: profile.icon).font(.caption2)
            Text(profile.name).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint.opacity(0.18), in: Capsule())
        .foregroundStyle(tint)
    }
    private var tint: Color {
        switch profile.tint {
        case "orange": return Color(red: 0.831, green: 0.627, blue: 0.329) // spark #D4A054
        case "purple": return Color(red: 0.639, green: 0.502, blue: 0.831) // muted purple
        case "gray":   return Color(red: 0.486, green: 0.510, blue: 0.565) // titanium #7C8290
        case "blue":   return Color(red: 0.353, green: 0.784, blue: 0.839) // accent #5AC8D6
        default:       return Color(red: 0.353, green: 0.784, blue: 0.839)
        }
    }
}

public struct ConnectStatusPill: View {
    public enum Phase { case online, connecting, offline }
    let phase: Phase
    public init(phase: Phase) { self.phase = phase }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(color.opacity(0.4), lineWidth: 6)
                        .scaleEffect(phase == .connecting ? 1.6 : 1)
                        .opacity(phase == .connecting ? 0 : 0.4)
                        .animation(
                            phase == .connecting
                            ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                            value: phase
                        )
                )
            Text(label).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.600)) // textSecondary #8E8E99
        }
    }
    private var color: Color {
        switch phase {
        case .online: return Color(red: 0.353, green: 0.784, blue: 0.839)     // accent #5AC8D6
        case .connecting: return Color(red: 0.831, green: 0.627, blue: 0.329) // spark #D4A054
        case .offline: return Color(red: 0.878, green: 0.361, blue: 0.310)    // error #E05C4F
        }
    }
    private var label: String {
        switch phase {
        case .online: return "online"
        case .connecting: return "connecting"
        case .offline: return "offline"
        }
    }
}
#endif
