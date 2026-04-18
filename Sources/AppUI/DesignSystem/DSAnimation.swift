#if canImport(UIKit)
import SwiftUI
import UIKit

extension DS {
    enum Animation {
        static let quick    = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let smooth   = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let pulse    = SwiftUI.Animation.easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
    }

    enum Transition {
        static let fade    = AnyTransition.opacity
        static let slideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)
        static let scale   = AnyTransition.scale(scale: 0.95).combined(with: .opacity)
    }

    enum Haptic {
        static func tap() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
#endif
