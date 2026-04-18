#if canImport(UIKit)
import SwiftUI

extension DS {
    enum Shadow {
        static func subtle(_ content: some View) -> some View {
            content.shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
        static func elevated(_ content: some View) -> some View {
            content.shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        }
        static func glow(_ content: some View, color: SwiftUI.Color = DS.Color.accent) -> some View {
            content.shadow(color: color.opacity(0.20), radius: 8, x: 0, y: 0)
        }
    }
}

extension View {
    func dsShadowSubtle() -> some View { DS.Shadow.subtle(self) }
    func dsShadowElevated() -> some View { DS.Shadow.elevated(self) }
    func dsShadowGlow(color: Color = DS.Color.accent) -> some View { DS.Shadow.glow(self, color: color) }
}
#endif
