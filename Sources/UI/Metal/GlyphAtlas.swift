#if canImport(UIKit)
import Foundation
import UIKit
import CoreText
import CoreGraphics
import Metal

public struct GlyphMetrics: Sendable {
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let ascent: CGFloat
}

public final class GlyphAtlas {
    public let metrics: GlyphMetrics
    public let texture: MTLTexture
    public let textureSize: CGSize
    private let device: MTLDevice
    private let font: CTFont
    private let scale: CGFloat
    private var entries: [UInt32: CGRect] = [:]
    private var cursorX: CGFloat = 0
    private var cursorY: CGFloat = 0
    private var rowHeight: CGFloat
    private let bitmap: UnsafeMutablePointer<UInt8>
    private let bytesPerRow: Int
    private let width: Int
    private let height: Int

    public init(device: MTLDevice, fontSize: CGFloat, scale: CGFloat = UIScreen.main.scale) {
        self.device = device
        self.scale = scale
        let f = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        self.font = f
        let glyphs: [CGGlyph] = [Self.glyph(for: "M", font: f)]
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(f, .horizontal, glyphs, &advance, 1)
        let cw = ceil(advance.width)
        let ch = ceil(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f))
        self.metrics = GlyphMetrics(
            cellWidth: cw,
            cellHeight: ch,
            ascent: CTFontGetAscent(f)
        )
        self.rowHeight = ch * scale + 2

        let w = 2048
        let h = 2048
        self.width = w
        self.height = h
        self.textureSize = CGSize(width: w, height: h)
        self.bytesPerRow = w
        self.bitmap = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h)
        self.bitmap.initialize(repeating: 0, count: w * h)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .a8Unorm,
            width: w, height: h, mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        self.texture = device.makeTexture(descriptor: desc)!

        for u in 0x20...0x7e { _ = self.region(for: UInt32(u)) }
        commitBitmap()
    }

    deinit {
        bitmap.deinitialize(count: width * height)
        bitmap.deallocate()
    }

    public func region(for codepoint: UInt32) -> CGRect {
        if let r = entries[codepoint] { return r }
        let glyphCellW = metrics.cellWidth * scale
        let glyphCellH = metrics.cellHeight * scale
        if cursorX + glyphCellW > CGFloat(width) {
            cursorX = 0
            cursorY += rowHeight
        }
        if cursorY + glyphCellH > CGFloat(height) {
            return entries[0x20] ?? .zero
        }
        rasterise(codepoint: codepoint, atX: cursorX, atY: cursorY,
                  cellW: glyphCellW, cellH: glyphCellH)
        let rect = CGRect(x: cursorX, y: cursorY, width: glyphCellW, height: glyphCellH)
        entries[codepoint] = rect
        cursorX += glyphCellW
        commitBitmap()
        return rect
    }

    public func uvRect(for codepoint: UInt32) -> CGRect {
        let r = region(for: codepoint)
        return CGRect(
            x: r.minX / CGFloat(width),
            y: r.minY / CGFloat(height),
            width: r.width / CGFloat(width),
            height: r.height / CGFloat(height)
        )
    }

    private func rasterise(codepoint: UInt32, atX x: CGFloat, atY y: CGFloat,
                           cellW: CGFloat, cellH: CGFloat) {
        guard let scalar = Unicode.Scalar(codepoint) else { return }
        let str = String(scalar)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: bitmap.advanced(by: Int(y) * bytesPerRow + Int(x)),
            width: Int(cellW), height: Int(cellH),
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: cs, bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(gray: 1, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: UIColor.white
        ]
        let astr = NSAttributedString(string: str, attributes: attrs)
        let line = CTLineCreateWithAttributedString(astr)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, ctx)
    }

    private func commitBitmap() {
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        texture.replace(region: region, mipmapLevel: 0, withBytes: bitmap, bytesPerRow: bytesPerRow)
    }

    private static func glyph(for s: String, font: CTFont) -> CGGlyph {
        var ch = unichar(s.utf16.first ?? 0x4d)
        var g: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1)
        return g
    }
}
#endif
