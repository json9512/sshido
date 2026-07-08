#if canImport(UIKit)
import SwiftUI

extension DS {
    enum Animation {
        static let quick    = SwiftUI.Animation.easeOut(duration: 0.15)
        static let pulse    = SwiftUI.Animation.easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
    }
}
#endif
