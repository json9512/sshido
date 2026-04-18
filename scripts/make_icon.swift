import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

let rect = CGRect(x: 0, y: 0, width: size, height: size)

let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1),
        CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let inset: CGFloat = 160
let glyph = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)

let font = NSFont.monospacedSystemFont(ofSize: 520, weight: .heavy)
let text = ">_"
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.353, green: 0.784, blue: 0.839, alpha: 1),
    .paragraphStyle: para,
    .kern: -30
]
let astr = NSAttributedString(string: text, attributes: attrs)

let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let line = CTLineCreateWithAttributedString(astr)
let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
let x = glyph.midX - bounds.midX
let y = glyph.midY - bounds.midY
ctx.textPosition = CGPoint(x: x, y: y)
CTLineDraw(line, ctx)
NSGraphicsContext.restoreGraphicsState()

guard let img = ctx.makeImage() else { fatalError("img") }
let rep = NSBitmapImageRep(cgImage: img)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
