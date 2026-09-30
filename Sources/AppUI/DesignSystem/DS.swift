#if canImport(UIKit)
import SwiftUI

enum DS {
    enum Color {
        static let void = SwiftUI.Color(hex: 0x0B0C0E)
        static let surface0 = SwiftUI.Color(hex: 0x0F1013)
        static let surface1 = SwiftUI.Color(hex: 0x191B20)
        static let surface2 = SwiftUI.Color(hex: 0x23262D)
        static let line = SwiftUI.Color(hex: 0x2A2D35)

        static let textPrimary = SwiftUI.Color(hex: 0xECEDEF)
        static let textSecondary = SwiftUI.Color(hex: 0xA3A7B0)
        static let textTertiary = SwiftUI.Color(hex: 0x7C818C)
        static let textOnAccent = SwiftUI.Color(hex: 0x082024)

        static let accent = SwiftUI.Color(hex: 0x5AC8D6)
        static let accentMuted = SwiftUI.Color(hex: 0x5AC8D6).opacity(0.14)
        static let success = SwiftUI.Color(hex: 0x4CC38A)
        static let error = SwiftUI.Color(hex: 0xF0716B)
        static let warning = SwiftUI.Color(hex: 0xE8B45A)
    }

    enum Font {
        static let family = "Geist"
        static let monoFamily = "Geist Mono"

        static func sans(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular, relativeTo style: SwiftUI.Font.TextStyle = .body) -> SwiftUI.Font {
            .custom(family, size: size, relativeTo: style).weight(weight)
        }

        static func mono(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular, relativeTo style: SwiftUI.Font.TextStyle = .body) -> SwiftUI.Font {
            .custom(monoFamily, size: size, relativeTo: style).weight(weight)
        }

        static let display = sans(30, .bold, relativeTo: .largeTitle)
        static let title = sans(20, .semibold, relativeTo: .title3)
        static let headline = sans(17, .semibold, relativeTo: .headline)
        static let rowTitle = sans(16, .medium, relativeTo: .body)
        static let body = sans(15, relativeTo: .body)
        static let callout = sans(14, relativeTo: .callout)
        static let caption = sans(12, relativeTo: .caption)
        static let captionMedium = sans(12, .semibold, relativeTo: .caption)
        static let label = sans(12, .semibold, relativeTo: .caption)
        static let monoBody = mono(14, .medium, relativeTo: .body)
        static let monoSmall = mono(12, relativeTo: .caption)
    }

    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 12
        static let small: CGFloat = 8
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Motion {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85)
    }

    static let hitTarget: CGFloat = 44
}

extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
#endif
