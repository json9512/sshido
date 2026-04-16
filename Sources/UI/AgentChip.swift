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
        case "orange": return .orange
        case "purple": return .purple
        case "gray":   return .gray
        case "blue":   return .blue
        default:       return .accentColor
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
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }
    private var color: Color {
        switch phase {
        case .online: return .green
        case .connecting: return .yellow
        case .offline: return .red
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
