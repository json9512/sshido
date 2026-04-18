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
        case "orange": return Color(red: 232/255, green: 145/255, blue: 90/255)  // spark
        case "purple": return .purple
        case "gray":   return Color(red: 124/255, green: 130/255, blue: 144/255) // titanium
        case "blue":   return Color(red: 74/255,  green: 158/255, blue: 255/255) // accent
        default:       return Color(red: 74/255,  green: 158/255, blue: 255/255)
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
                .foregroundStyle(Color(red: 142/255, green: 142/255, blue: 153/255))
        }
    }
    private var color: Color {
        switch phase {
        case .online: return Color(red: 52/255, green: 199/255, blue: 89/255)
        case .connecting: return Color(red: 255/255, green: 214/255, blue: 10/255)
        case .offline: return Color(red: 255/255, green: 69/255, blue: 58/255)
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
