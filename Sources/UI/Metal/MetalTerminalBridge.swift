#if canImport(UIKit)
import Foundation
import UIKit
import simd
import SwiftTerm
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoModels)
import sshidoModels
#endif

@MainActor
public final class MetalTerminalBridge: NSObject, TerminalBridge, TerminalGridSource {
    public let renderer: MetalTerminalRenderer
    public let view: MetalTerminalView
    public var terminal: SwiftTerm.Terminal!

    private let channel: SSHChannel
    private var readerTask: Task<Void, Never>?
    private var hasStartedConnect = false
    private var lastReportedSize: (cols: Int, rows: Int) = (0, 0)
    private let delegateRelay = TerminalDelegateRelay()
    private var appearanceObserver: NSObjectProtocol?
    private var appearanceTask: Task<Void, Never>?
    private var lastTitle: String = ""

    public let activityTracker = TerminalActivityTracker()
    public var onTitleChange: ((String) -> Void)?

    public init?(channel: SSHChannel) {
        self.channel = channel
        guard let r = MetalTerminalRenderer(fontSize: 12) else {
            Log.ui.error("Metal device unavailable — cannot create terminal bridge")
            return nil
        }
        self.renderer = r
        let v = MetalTerminalView(renderer: r)
        self.view = v
        let opts = TerminalOptions(cols: 80, rows: 24, scrollback: 5000)
        super.init()
        self.terminal = SwiftTerm.Terminal(delegate: delegateRelay, options: opts)
        self.delegateRelay.owner = self
        self.delegateRelay.channel = channel
        renderer.source = self
        v.bridge = self
        renderer.start()
        startReader()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .sshidoAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleApplyAppearance() }
        }
        scheduleApplyAppearance()
    }

    deinit {
        readerTask?.cancel()
        appearanceTask?.cancel()
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func scheduleApplyAppearance() {
        appearanceTask?.cancel()
        appearanceTask = Task { @MainActor [weak self] in
            await self?.applyAppearance()
        }
    }

    public var cols: Int { terminal.cols }
    public var rows: Int { terminal.rows }
    public var isApplicationCursor: Bool { terminal.applicationCursor }

    public func charAt(col: Int, row: Int) -> (codepoint: UInt32, fg: SIMD4<Float>, bg: SIMD4<Float>) {
        guard let cd = terminal.getCharData(col: col, row: row) else {
            return (0x20, defaultForeground, defaultBackground)
        }
        let raw = UInt32(bitPattern: Int32(cd.unicodeScalarCode))
        let cp: UInt32 = (raw == 0 || raw > 0x10FFFF) ? 0x20 : raw
        let fg = colorToVec(cd.attribute.fg, fallback: defaultForeground)
        let bg = colorToVec(cd.attribute.bg, fallback: defaultBackground)
        if cd.attribute.style.contains(.inverse) {
            return (cp, bg, fg)
        }
        return (cp, fg, bg)
    }

    public func widthAt(col: Int, row: Int) -> Int {
        guard let cd = terminal.getCharData(col: col, row: row) else { return 1 }
        let raw = UInt32(bitPattern: Int32(cd.unicodeScalarCode))
        return isWideCodepoint(raw) ? 2 : 1
    }

    public func cursorCell() -> (col: Int, row: Int)? {
        let loc = terminal.getCursorLocation()
        return (loc.x, loc.y)
    }

    public var defaultBackground: SIMD4<Float> { SIMD4(0.137, 0.137, 0.145, 1) } // #232325
    public var defaultForeground: SIMD4<Float> { SIMD4(0.88, 0.88, 0.88, 1) }

    public func isSelected(col: Int, row: Int) -> Bool {
        view.isCellSelected(col: col, row: row)
    }

    public func feed(_ data: Data) {
        terminal.feed(byteArray: Array(data))
        renderer.setNeedsRender()
        activityTracker.onDataReceived(byteCount: data.count)
    }

    public func refit() {
        renderer.setNeedsRender()
    }

    public func focus() {
        _ = view.becomeFirstResponder()
    }

    public func applyAppearance() async {
        let appearance = await AppearanceStore.shared.appearance
        renderer.updateFontSize(CGFloat(appearance.fontSize))
        view.returnKeyType = {
            switch appearance.returnKeyStyle {
            case .defaultReturn: return .default
            case .send:          return .send
            case .done:          return .done
            case .go:            return .go
            case .newline:       return .default
            }
        }()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        renderer.setNeedsRender()
    }

    fileprivate func receiveTitleFromTerminal(_ raw: String) {
        let cleaned = raw
            .replacingOccurrences(of: "\u{0007}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != lastTitle else { return }
        let display = cleaned.count > 80 ? String(cleaned.prefix(80)) : cleaned
        lastTitle = display
        onTitleChange?(display)
    }

    public func copyFromTerminal(_ kind: CopyKind) async -> String {
        switch kind {
        case .selection:
            return view.selectedText() ?? ""
        case .viewport:
            return buildViewportDump()
        case .lastURL:
            return findLastURL()
        }
    }

    private func buildViewportDump() -> String {
        var lines: [String] = []
        for r in 0..<terminal.rows {
            if let line = terminal.getLine(row: r) {
                var s = ""
                for c in 0..<terminal.cols {
                    let cd = line[c]
                    if let scalar = Unicode.Scalar(cd.unicodeScalarCode) {
                        s.append(Character(scalar))
                    }
                }
                lines.append(s.trimmingCharacters(in: .whitespaces))
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findLastURL() -> String {
        let yDisp = terminal.buffer.yDisp
        let scanStart = max(0, yDisp - 50)
        let scanEnd = yDisp + max(terminal.rows, 50)
        var flat = ""
        for r in scanStart..<scanEnd {
            guard let line = terminal.getScrollInvariantLine(row: r) else { continue }
            var s = ""
            for c in 0..<terminal.cols {
                let cd = line[c]
                let code = cd.getCharacter()
                if code != "\0" {
                    s.append(code)
                }
            }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flat.append(" ")
            } else {
                flat.append(trimmed)
            }
        }
        let pattern = #"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(flat.startIndex..., in: flat)
        let matches = regex.matches(in: flat, range: range)
        guard let last = matches.last,
              let r = Range(last.range, in: flat) else { return "" }
        return String(flat[r])
    }

    public func sendBytes(_ bytes: [UInt8]) {
        channel.enqueueInput(bytes)
    }

    public func resizeIfChanged(cols: Int, rows: Int) {
        guard cols > 0, rows > 0,
              (cols, rows) != lastReportedSize else { return }
        lastReportedSize = (cols, rows)
        terminal.resize(cols: cols, rows: rows)
        if let citadel = channel as? CitadelSSHChannel {
            citadel.setInitialSize(cols: cols, rows: rows)
        }
        if !hasStartedConnect {
            hasStartedConnect = true
            Task { try? await channel.connect() }
        } else {
            Task { try? await channel.resize(cols: cols, rows: rows) }
        }
        renderer.setNeedsRender()
    }

    public func requestServerRedraw() {
        channel.enqueueInput(Array("\u{0c}".utf8))
    }

    public func invalidateReportedSize() {
        lastReportedSize = (0, 0)
    }

    private func startReader() {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            guard let self else { return }
            var firstChunk = true
            for await chunk in channel.output {
                await MainActor.run {
                    if firstChunk {
                        firstChunk = false
                        self.activityTracker.onConnected()
                    }
                    self.feed(chunk)
                }
            }
            await MainActor.run { self.activityTracker.onDisconnected() }
        }
    }

    private func colorToVec(_ c: Attribute.Color, fallback: SIMD4<Float>) -> SIMD4<Float> {
        switch c {
        case .defaultColor, .defaultInvertedColor:
            return fallback
        case .ansi256(let code):
            return ansi256(code)
        case .trueColor(let r, let g, let b):
            return SIMD4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        }
    }

    private func ansi256(_ code: UInt8) -> SIMD4<Float> {
        if code < 16 { return basicColor(code) }
        if code >= 16 && code <= 231 {
            let n = Int(code) - 16
            let r = n / 36
            let g = (n % 36) / 6
            let b = n % 6
            let scale: (Int) -> Float = { i in i == 0 ? 0 : Float(40 * i + 55) / 255 }
            return SIMD4(scale(r), scale(g), scale(b), 1)
        }
        let v = Float(8 + 10 * (Int(code) - 232)) / 255
        return SIMD4(v, v, v, 1)
    }

    private func basicColor(_ c: UInt8) -> SIMD4<Float> {
        let table: [SIMD4<Float>] = [
            SIMD4(0,0,0,1),         SIMD4(0.8,0.18,0.18,1), SIMD4(0.05,0.74,0.47,1), SIMD4(0.9,0.8,0.06,1),
            SIMD4(0.14,0.45,0.78,1),SIMD4(0.74,0.25,0.74,1),SIMD4(0.07,0.66,0.8,1),  SIMD4(0.9,0.9,0.9,1),
            SIMD4(0.4,0.4,0.4,1),   SIMD4(0.94,0.3,0.3,1),  SIMD4(0.14,0.82,0.55,1), SIMD4(0.96,0.96,0.26,1),
            SIMD4(0.23,0.56,0.92,1),SIMD4(0.84,0.44,0.84,1),SIMD4(0.16,0.72,0.86,1), SIMD4(1,1,1,1)
        ]
        return table[Int(c) % table.count]
    }
}

private extension CharData {
    var unicodeScalarCode: Int { self.getCharacter().unicodeScalars.first.map { Int($0.value) } ?? 0x20 }
}

private final class TerminalDelegateRelay: TerminalDelegate {
    weak var owner: MetalTerminalBridge?
    var channel: SSHChannel?
    func send(source: SwiftTerm.Terminal, data: ArraySlice<UInt8>) {
        channel?.enqueueInput(Array(data))
    }
    func showCursor(source: SwiftTerm.Terminal) {
        Task { @MainActor in self.owner?.renderer.setNeedsRender() }
    }
    func hideCursor(source: SwiftTerm.Terminal) {
        Task { @MainActor in self.owner?.renderer.setNeedsRender() }
    }
    func windowCommand(source: SwiftTerm.Terminal, command: SwiftTerm.Terminal.WindowManipulationCommand) -> [UInt8]? {
        switch command {
        case .reportTextAreaPixelDimension,
             .reportTerminalWindowPixelDimension,
             .reportSizeOfScreenInPixels,
             .reportCellSizeInPixels,
             .reportTextAreaCharacters,
             .reportScreenSizeCharacters,
             .reportIconLabel,
             .reportWindowTitle,
             .reportTerminalState,
             .reportTerminalPosition,
             .reportTextAreaPosition:
            return []
        default:
            return nil
        }
    }
    func iTermContent(source: SwiftTerm.Terminal, content: ArraySlice<UInt8>) {}
    func setTerminalTitle(source: SwiftTerm.Terminal, title: String) {
        Task { @MainActor in self.owner?.receiveTitleFromTerminal(title) }
    }
    func setTerminalIconTitle(source: SwiftTerm.Terminal, title: String) {
        Task { @MainActor in self.owner?.receiveTitleFromTerminal(title) }
    }
}
#endif
