#if canImport(UIKit)
import UIKit
import ImageIO

/// Loads sprite frames from a horizontal PNG strip or an animated GIF.
@MainActor
public final class SpriteSheet {
    public let frameSize: CGSize
    public let frameCount: Int

    /// GIF-based: pre-extracted frames. PNG-based: nil (cropped on demand from sheet).
    private var gifFrames: [UIImage]?
    private var sheet: CGImage?
    private var cache: [Int: UIImage] = [:]

    /// FPS extracted from GIF frame durations (average). Nil for PNG strips.
    public private(set) var extractedFPS: Double?
    /// Whether the GIF is set to loop.
    public private(set) var extractedLooping: Bool = true

    // MARK: - PNG strip initializers

    /// Loads a PNG sprite strip from the module bundle.
    public init?(named name: String, frameSize: CGSize, bundle: Bundle? = nil) {
        let resolvedBundle: Bundle
        if let bundle {
            resolvedBundle = bundle
        } else {
            #if SWIFT_PACKAGE
            resolvedBundle = .module
            #else
            resolvedBundle = .main
            #endif
        }
        if let url = resolvedBundle.url(forResource: name, withExtension: "gif"),
           let loaded = SpriteSheet.loadGIF(from: url) {
            self.gifFrames = loaded.frames
            self.frameSize = CGSize(width: loaded.frames[0].size.width, height: loaded.frames[0].size.height)
            self.frameCount = loaded.frames.count
            self.extractedFPS = loaded.fps
            self.extractedLooping = loaded.looping
            return
        }
        guard let url = resolvedBundle.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return nil }
        self.sheet = cg
        self.frameSize = frameSize
        self.frameCount = max(1, cg.width / Int(frameSize.width))
    }

    /// Load a PNG sprite strip from a file URL on disk.
    public init?(fileURL: URL, frameSize: CGSize) {
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return nil }
        self.sheet = cg
        self.frameSize = frameSize
        self.frameCount = max(1, cg.width / Int(frameSize.width))
    }

    /// Initialize directly from a CGImage.
    public init(cgImage: CGImage, frameSize: CGSize) {
        self.sheet = cgImage
        self.frameSize = frameSize
        self.frameCount = max(1, cgImage.width / Int(frameSize.width))
    }

    // MARK: - GIF initializers

    /// Load an animated GIF from a file URL. Frame size, count, FPS, and looping
    /// are all extracted automatically from the GIF metadata.
    public init?(gifURL: URL) {
        guard let loaded = SpriteSheet.loadGIF(from: gifURL) else { return nil }
        self.gifFrames = loaded.frames
        let first = loaded.frames[0]
        self.frameSize = CGSize(width: first.size.width, height: first.size.height)
        self.frameCount = loaded.frames.count
        self.extractedFPS = loaded.fps
        self.extractedLooping = loaded.looping
    }

    /// Load an animated GIF from raw data.
    public init?(gifData: Data) {
        guard let loaded = SpriteSheet.loadGIFData(gifData) else { return nil }
        self.gifFrames = loaded.frames
        let first = loaded.frames[0]
        self.frameSize = CGSize(width: first.size.width, height: first.size.height)
        self.frameCount = loaded.frames.count
        self.extractedFPS = loaded.fps
        self.extractedLooping = loaded.looping
    }

    // MARK: - Frame access

    public func frame(at index: Int) -> UIImage {
        let clamped = max(0, min(index, frameCount - 1))

        if let gifFrames {
            return gifFrames[clamped]
        }

        if let cached = cache[clamped] { return cached }
        guard let sheet else { return UIImage() }
        let x = clamped * Int(frameSize.width)
        let rect = CGRect(x: x, y: 0, width: Int(frameSize.width), height: Int(frameSize.height))
        guard let cropped = sheet.cropping(to: rect) else { return UIImage() }
        let img = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        cache[clamped] = img
        return img
    }

    // MARK: - GIF loading (ImageIO)

    private struct GIFLoad {
        let frames: [UIImage]
        let fps: Double
        let looping: Bool
    }

    private static func loadGIF(from url: URL) -> GIFLoad? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return loadGIFData(data)
    }

    private static func loadGIFData(_ data: Data) -> GIFLoad? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage, scale: 1, orientation: .up))

            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                let delay = (gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (gifProps[kCGImagePropertyGIFDelayTime] as? Double)
                    ?? 0.1
                totalDuration += max(delay, 0.02) // GIF spec minimum
            } else {
                totalDuration += 0.1
            }
        }

        guard !frames.isEmpty else { return nil }

        let avgDelay = totalDuration / Double(frames.count)
        let fps = 1.0 / avgDelay

        var looping = true
        if let globalProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gifGlobal = globalProps[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let loopCount = gifGlobal[kCGImagePropertyGIFLoopCount] as? Int {
            looping = loopCount == 0 // 0 = infinite loop
        }

        return GIFLoad(frames: frames, fps: fps, looping: looping)
    }
}
#endif
