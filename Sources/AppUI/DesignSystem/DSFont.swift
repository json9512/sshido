#if canImport(UIKit)
import SwiftUI

extension DS {
    enum Font {
        static let displayLarge = SwiftUI.Font.system(size: 28, weight: .bold)
        static let headline     = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body         = SwiftUI.Font.system(size: 15, weight: .regular)
        static let callout      = SwiftUI.Font.system(size: 14, weight: .regular)
        static let caption      = SwiftUI.Font.system(size: 12, weight: .regular)
        static let captionMedium = SwiftUI.Font.system(size: 12, weight: .medium)
        static let mono         = SwiftUI.Font.system(size: 14, weight: .medium, design: .monospaced)
        static let monoSmall    = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let chip         = SwiftUI.Font.system(size: 13, weight: .medium, design: .monospaced)
    }
}
#endif
