#if canImport(UIKit)
import SwiftUI

extension DS {
    enum Shadow {
        static func subtle(_ content: some View) -> some View {
            content.shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
    }
}

extension View {
    func dsShadowSubtle() -> some View { DS.Shadow.subtle(self) }
}
#endif
