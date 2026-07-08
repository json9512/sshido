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
#endif
