#if canImport(UIKit)
import SwiftUI
import simd

extension DS {
    enum Color {
        // MARK: - Surfaces (darkest to lightest)
        static let void       = SwiftUI.Color(hex: 0x1E1E22)
        static let surface0   = SwiftUI.Color(hex: 0x111114)
        static let surface1   = SwiftUI.Color(hex: 0x1A1A1F)
        static let surface2   = SwiftUI.Color(hex: 0x242429)
        static let surface3   = SwiftUI.Color(hex: 0x2E2E35)

        // MARK: - Text
        static let textPrimary   = SwiftUI.Color(hex: 0xE8E8ED)
        static let textSecondary = SwiftUI.Color(hex: 0x8E8E99)
        static let textTertiary  = SwiftUI.Color(hex: 0x5C5C66)
        static let textOnAccent  = SwiftUI.Color.white

        // MARK: - Titanium (metallic signature)
        static let titanium      = SwiftUI.Color(hex: 0x7C8290)
        static let titaniumLight = SwiftUI.Color(hex: 0xA8ADBA)
        static let titaniumDark  = SwiftUI.Color(hex: 0x4A4E58)

        // MARK: - Accent (cool blue)
        static let accent      = SwiftUI.Color(hex: 0x4A9EFF)
        static let accentMuted = SwiftUI.Color(hex: 0x4A9EFF).opacity(0.15)
        static let accentHover = SwiftUI.Color(hex: 0x6BB3FF)

        // MARK: - Spark (warm secondary)
        static let spark      = SwiftUI.Color(hex: 0xE8915A)
        static let sparkMuted = SwiftUI.Color(hex: 0xE8915A).opacity(0.15)

        // MARK: - Semantic
        static let success = SwiftUI.Color(hex: 0x34C759)
        static let error   = SwiftUI.Color(hex: 0xFF453A)
        static let warning = SwiftUI.Color(hex: 0xFFD60A)

        // MARK: - Shimmer (Metal chrome)
        static let shimmerBase      = surface1
        static let shimmerHighlight = titaniumLight.opacity(0.06)
    }
}

// MARK: - SIMD helpers for Metal consumption

extension DS.Color {
    static let voidSIMD:     SIMD4<Float> = simd(0x1E1E22)
    static let surface0SIMD: SIMD4<Float> = simd(0x111114)
    static let surface1SIMD: SIMD4<Float> = simd(0x1A1A1F)

    private static func simd(_ hex: UInt32) -> SIMD4<Float> {
        let r = Float((hex >> 16) & 0xFF) / 255.0
        let g = Float((hex >> 8)  & 0xFF) / 255.0
        let b = Float(hex         & 0xFF) / 255.0
        return SIMD4<Float>(r, g, b, 1.0)
    }
}

// MARK: - Color(hex:) initializer

extension SwiftUI.Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
#endif
