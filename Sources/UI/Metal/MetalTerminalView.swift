#if canImport(UIKit)
import UIKit
import QuartzCore
import SwiftTerm
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
final class TerminalInputProxy: UITextView {
    weak var bridge: MetalTerminalBridge?

    override func deleteBackward() {
        if (text ?? "").isEmpty && markedTextRange == nil {
            bridge?.activityTracker.onUserInput()
            bridge?.sendBytes([0x7f])
            return
        }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(kEsc)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(kUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(kDown)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(kLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(kRight)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(kTab)),
            UIKeyCommand(input: "c", modifierFlags: .control, action: #selector(kCtrlC)),
            UIKeyCommand(input: "d", modifierFlags: .control, action: #selector(kCtrlD)),
            UIKeyCommand(input: "z", modifierFlags: .control, action: #selector(kCtrlZ)),
            UIKeyCommand(input: "l", modifierFlags: .control, action: #selector(kCtrlL)),
            UIKeyCommand(input: "\u{8}", modifierFlags: .alternate, action: #selector(kAltDelete))
        ]
    }
    @objc private func kEsc()   { bridge?.sendBytes([0x1b]) }
    @objc private func kUp()    { bridge?.sendBytes([0x1b, 0x5b, 0x41]) }
    @objc private func kDown()  { bridge?.sendBytes([0x1b, 0x5b, 0x42]) }
    @objc private func kRight() { bridge?.sendBytes([0x1b, 0x5b, 0x43]) }
    @objc private func kLeft()  { bridge?.sendBytes([0x1b, 0x5b, 0x44]) }
    @objc private func kTab()   { bridge?.sendBytes([0x09]) }
    @objc private func kCtrlC() { bridge?.sendBytes([0x03]) }
    @objc private func kCtrlD() { bridge?.sendBytes([0x04]) }
    @objc private func kCtrlZ() { bridge?.sendBytes([0x1a]) }
    @objc private func kCtrlL() { bridge?.sendBytes([0x0c]) }
    @objc private func kAltDelete() { bridge?.sendBytes([0x1b, 0x7f]) }
}

// Container that swallows Metal output visually on top of the UITextView input
// proxy. Pass-through so touches reach the proxy underneath.
final class MetalOverlayView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

@MainActor
public final class MetalTerminalView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    public let renderer: MetalTerminalRenderer
    public weak var bridge: MetalTerminalBridge? {
        didSet { inputProxy.bridge = bridge }
    }

    private let inputProxy = TerminalInputProxy()
    private let metalOverlay = MetalOverlayView()

    public var returnKeyType: UIReturnKeyType {
        get { inputProxy.returnKeyType }
        set {
            inputProxy.returnKeyType = newValue
            if inputProxy.isFirstResponder { inputProxy.reloadInputViews() }
        }
    }

    public var returnSendsNewline = false

    private var pinchBaseFontSize: CGFloat = 16
    private var keyboardOverlap: CGFloat = 0
    private var lastLayoutSize: CGSize = .zero
    private var lastTapCell: (col: Int, row: Int)?

    public init(renderer: MetalTerminalRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.137, green: 0.137, blue: 0.145, alpha: 1)

        inputProxy.autocorrectionType = .no
        inputProxy.autocapitalizationType = .none
        inputProxy.spellCheckingType = .no
        inputProxy.keyboardAppearance = .dark
        inputProxy.textColor = .clear
        inputProxy.tintColor = .clear
        inputProxy.backgroundColor = .clear
        inputProxy.text = ""
        inputProxy.delegate = self
        addSubview(inputProxy)

        metalOverlay.backgroundColor = .clear
        metalOverlay.layer.addSublayer(renderer.metalLayer)
        addSubview(metalOverlay)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        let long = UILongPressGestureRecognizer(target: self, action: #selector(didLong(_:)))
        long.minimumPressDuration = 0.4
        addGestureRecognizer(long)

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var canBecomeFirstResponder: Bool { true }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        inputProxy.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        inputProxy.resignFirstResponder()
    }

    public override var inputAssistantItem: UITextInputAssistantItem {
        let item = inputProxy.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }

    // shouldChangeTextIn fires only for commits (ASCII typing, IME syllable
    // commits, and deletions). It does NOT fire during IME marked-text
    // composition. Do not mutate textView.text here during composition — it
    // destroys the IME context.
    public func textView(_ textView: UITextView,
                         shouldChangeTextIn range: NSRange,
                         replacementText text: String) -> Bool {
        bridge?.activityTracker.onUserInput()

        if text.isEmpty {
            let tail = hangul.flush()
            if !tail.isEmpty { bridge?.sendBytes(Array(tail.utf8)) }
            if range.length > 0 {
                bridge?.sendBytes(Array(repeating: 0x7f, count: range.length))
            }
            return true
        }

        if text == "\n" || text == "\r" || text == "\r\n" {
            let tail = hangul.flush()
            if !tail.isEmpty { bridge?.sendBytes(Array(tail.utf8)) }
            bridge?.sendBytes([returnSendsNewline ? 0x0a : 0x0d])
            textView.text = ""
            return false
        }

        // iOS gives us compatibility jamo (U+3131–U+318E) one at a time when
        // committing from Korean IME. Route through a Hangul composer that
        // builds syllables via state machine (choseong/jungseong/jongseong) and
        // emits composed Hangul (U+AC00–U+D7A3) on commit boundaries.
        let emitted = hangul.feed(text)
        if !emitted.isEmpty {
            bridge?.sendBytes(Array(emitted.utf8))
        }

        if (textView.text?.count ?? 0) > 1000 && textView.markedTextRange == nil {
            textView.text = ""
        }
        return true
    }

    private let hangul = HangulComposer()

    private var panAccum: CGFloat = 0
    @objc private func didPan(_ g: UIPanGestureRecognizer) {
        let cellW = renderer.glyphMetrics.cellWidth
        let cellH = renderer.glyphMetrics.cellHeight
        switch g.state {
        case .began:
            panAccum = 0
            if let bridge {
                let p = g.location(in: self)
                let col = max(0, min(bridge.cols - 1, Int(p.x / cellW)))
                let row = max(0, min(bridge.rows - 1, Int(p.y / cellH)))
                lastTapCell = (col, row)
            }
        case .changed:
            let dy = g.translation(in: self).y
            let lines = Int(dy / cellH)
            if lines != 0 {
                emitScroll(lines: lines)
                g.setTranslation(CGPoint(x: 0, y: dy - CGFloat(lines) * cellH), in: self)
            }
        default: break
        }
    }

    private func emitScroll(lines: Int) {
        guard let bridge else { return }
        if bridge.terminal.mouseMode != .off {
            let button = lines > 0 ? 64 : 65
            let cols = bridge.terminal.cols
            let rows = bridge.terminal.rows
            let col = lastTapCell.map { max(0, min(cols - 1, $0.col)) } ?? max(0, cols / 2)
            let row = lastTapCell.map { max(0, min(rows - 1, $0.row)) } ?? max(0, rows / 2)
            let reps = min(max(abs(lines) / 2, 1), 6)
            for _ in 0..<reps {
                bridge.terminal.sendEvent(buttonFlags: button, x: col, y: row)
            }
        } else if bridge.terminal.isCurrentBufferAlternate {
            return
        } else {
            let buf = bridge.terminal.buffer
            let new = max(0, buf.yDisp - lines)
            buf.yDisp = new
            renderer.setNeedsRender()
        }
    }

    @objc private func didPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchBaseFontSize = renderer.fontSize
        case .changed:
            renderer.updateFontSize(pinchBaseFontSize * g.scale)
            renderer.setNeedsRender()
        case .ended, .cancelled:
            renderer.updateFontSize(pinchBaseFontSize * g.scale)
            recomputeAndReportSize()
        default: break
        }
    }

    @objc private func didTap(_ g: UITapGestureRecognizer) {
        if !inputProxy.isFirstResponder {
            _ = inputProxy.becomeFirstResponder()
        }
        selectionStart = nil
        selectionEnd = nil
        if let bridge {
            let p = g.location(in: self)
            let cellW = renderer.glyphMetrics.cellWidth
            let cellH = renderer.glyphMetrics.cellHeight
            let col = max(0, min(bridge.cols - 1, Int(p.x / cellW)))
            let row = max(0, min(bridge.rows - 1, Int(p.y / cellH)))
            lastTapCell = (col, row)
            if bridge.terminal.mouseMode != .off {
                bridge.terminal.sendEvent(buttonFlags: 0, x: col, y: row)
                bridge.terminal.sendEvent(buttonFlags: 3, x: col, y: row)
            }
        }
        renderer.setNeedsRender()
    }

    private var selectionStart: (col: Int, row: Int)?
    private var selectionEnd: (col: Int, row: Int)?

    public var hasSelection: Bool { selectionStart != nil && selectionEnd != nil }

    @objc private func didLong(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: self)
        let cellW = renderer.glyphMetrics.cellWidth
        let cellH = renderer.glyphMetrics.cellHeight
        let col = max(0, min((bridge?.cols ?? 1) - 1, Int(p.x / cellW)))
        let row = max(0, min((bridge?.rows ?? 1) - 1, Int(p.y / cellH)))
        switch g.state {
        case .began:
            selectionStart = (col, row)
            selectionEnd = (col, row)
        case .changed:
            selectionEnd = (col, row)
        default: break
        }
        renderer.setNeedsRender()
    }

    public func selectedText() -> String? {
        guard let s = selectionStart, let e = selectionEnd, let bridge else { return nil }
        let (start, end) = orderedSelection(s, e)
        var out = ""
        for r in start.row...end.row {
            guard let line = bridge.terminal.getLine(row: r) else { continue }
            let c0 = (r == start.row) ? start.col : 0
            let c1 = (r == end.row) ? end.col : (bridge.cols - 1)
            for c in c0...max(c0, c1) {
                let cd = line[c]
                out.append(cd.getCharacter())
            }
            if r != end.row { out.append("\n") }
        }
        return out
    }

    public func isCellSelected(col: Int, row: Int) -> Bool {
        guard let s = selectionStart, let e = selectionEnd else { return false }
        let (start, end) = orderedSelection(s, e)
        if row < start.row || row > end.row { return false }
        if row == start.row && row == end.row {
            return col >= start.col && col <= end.col
        }
        if row == start.row { return col >= start.col }
        if row == end.row { return col <= end.col }
        return true
    }

    private func orderedSelection(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int))
        -> ((col: Int, row: Int), (col: Int, row: Int)) {
        if a.row < b.row || (a.row == b.row && a.col <= b.col) {
            return (a, b)
        }
        return (b, a)
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let mine = convert(bounds, to: nil)
        keyboardOverlap = max(0, mine.maxY - f.minY)
        setNeedsLayout()
        layoutIfNeeded()
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardOverlap = 0
        setNeedsLayout()
        layoutIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let availableHeight = max(1, bounds.height - keyboardOverlap)
        let f = CGRect(x: 0, y: 0, width: bounds.width, height: availableHeight)
        inputProxy.frame = f
        metalOverlay.frame = f
        renderer.metalLayer.frame = metalOverlay.bounds
        let scale = renderer.metalLayer.contentsScale
        renderer.metalLayer.drawableSize = CGSize(
            width: max(1, f.width * scale),
            height: max(1, f.height * scale)
        )
        recomputeAndReportSize()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        bridge?.invalidateReportedSize()
        DispatchQueue.main.async { [weak self] in
            self?.recomputeAndReportSize()
            self?.renderer.setNeedsRender()
        }
    }

    private func recomputeAndReportSize() {
        let cellW = renderer.glyphMetrics.cellWidth
        let cellH = renderer.glyphMetrics.cellHeight
        guard cellW > 0, cellH > 0, bounds.width > 0 else { return }
        let availableHeight = max(1, bounds.height - keyboardOverlap)
        let cols = max(1, Int(bounds.width / cellW))
        let rows = max(1, Int(availableHeight / cellH))
        bridge?.resizeIfChanged(cols: cols, rows: rows)
    }
}

// Hangul syllable composer. Accepts a stream of compatibility jamo (U+3131–U+318E)
// interleaved with non-Hangul characters, and emits composed Hangul syllables
// (U+AC00–U+D7A3) plus pass-through for non-Hangul. Maintains one in-progress
// syllable state (choseong/jungseong/jongseong) across calls.
@MainActor
final class HangulComposer {
    private var cho: Int? = nil   // 0..18
    private var jung: Int? = nil  // 0..20
    private var jong: Int = 0     // 0=none, 1..27

    func feed(_ s: String) -> String {
        var out = ""
        for sc in s.unicodeScalars {
            let v = sc.value
            if let choIdx = choIndex[v], let jongIdx = jongIndex[v] {
                out += handleConsonant(choIdx: choIdx, jongIdx: jongIdx, raw: sc)
            } else if let choIdx = choIndex[v] {
                out += handleConsonant(choIdx: choIdx, jongIdx: nil, raw: sc)
            } else if let jongIdx = jongIndex[v] {
                out += handleConsonant(choIdx: nil, jongIdx: jongIdx, raw: sc)
            } else if let jungIdx = jungIndex[v] {
                out += handleVowel(jungIdx: jungIdx, raw: sc)
            } else {
                out += flush()
                out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    func flush() -> String {
        guard cho != nil || jung != nil || jong != 0 else { return "" }
        let result = currentSyllable()
        cho = nil; jung = nil; jong = 0
        return result
    }

    private func currentSyllable() -> String {
        if let c = cho, let j = jung {
            let code = 0xAC00 + c * 21 * 28 + j * 28 + jong
            return String(Unicode.Scalar(code)!)
        }
        if let c = cho, let code = compatFromCho[c] {
            return String(Unicode.Scalar(code)!)
        }
        if let j = jung, let code = compatFromJung[j] {
            return String(Unicode.Scalar(code)!)
        }
        if jong != 0, let code = compatFromJong[jong] {
            return String(Unicode.Scalar(code)!)
        }
        return ""
    }

    private func handleConsonant(choIdx: Int?, jongIdx: Int?, raw: Unicode.Scalar) -> String {
        if cho == nil {
            if let c = choIdx { cho = c; return "" }
            return flush() + String(raw)
        }
        if jung == nil {
            let prev = flush()
            if let c = choIdx { cho = c; return prev }
            return prev + String(raw)
        }
        if jong == 0, let jIdx = jongIdx {
            jong = jIdx
            return ""
        }
        if let jIdx = jongIdx, let combined = jongCompound[jong]?[jIdx] {
            jong = combined
            return ""
        }
        let prev = flush()
        if let c = choIdx { cho = c; return prev }
        return prev + String(raw)
    }

    private func handleVowel(jungIdx: Int, raw: Unicode.Scalar) -> String {
        if cho == nil {
            let prev = flush()
            return prev + String(raw)
        }
        if jung == nil {
            jung = jungIdx
            return ""
        }
        if jong != 0 {
            // Jong becomes initial of new syllable with this vowel.
            if let newCho = jongToCho[jong] {
                jong = 0
                let prev = currentSyllable()
                cho = newCho; jung = jungIdx
                return prev
            }
            if let (remain, movedCho) = jongSplit[jong] {
                jong = remain
                let prev = currentSyllable()
                cho = movedCho; jung = jungIdx; jong = 0
                return prev
            }
            let prev = flush()
            return prev + String(raw)
        }
        if let j = jung, let combined = jungCompound[j]?[jungIdx] {
            jung = combined
            return ""
        }
        let prev = flush()
        return prev + String(raw)
    }

    private let choIndex: [UInt32: Int] = [
        0x3131: 0, 0x3132: 1, 0x3134: 2, 0x3137: 3, 0x3138: 4, 0x3139: 5,
        0x3141: 6, 0x3142: 7, 0x3143: 8, 0x3145: 9, 0x3146: 10, 0x3147: 11,
        0x3148: 12, 0x3149: 13, 0x314A: 14, 0x314B: 15, 0x314C: 16,
        0x314D: 17, 0x314E: 18
    ]

    private let jungIndex: [UInt32: Int] = [
        0x314F: 0, 0x3150: 1, 0x3151: 2, 0x3152: 3, 0x3153: 4, 0x3154: 5,
        0x3155: 6, 0x3156: 7, 0x3157: 8, 0x3158: 9, 0x3159: 10, 0x315A: 11,
        0x315B: 12, 0x315C: 13, 0x315D: 14, 0x315E: 15, 0x315F: 16,
        0x3160: 17, 0x3161: 18, 0x3162: 19, 0x3163: 20
    ]

    private let jongIndex: [UInt32: Int] = [
        0x3131: 1, 0x3132: 2, 0x3133: 3, 0x3134: 4, 0x3135: 5, 0x3136: 6,
        0x3137: 7, 0x3139: 8, 0x313A: 9, 0x313B: 10, 0x313C: 11, 0x313D: 12,
        0x313E: 13, 0x313F: 14, 0x3140: 15, 0x3141: 16, 0x3142: 17, 0x3144: 18,
        0x3145: 19, 0x3146: 20, 0x3147: 21, 0x3148: 22, 0x314A: 23, 0x314B: 24,
        0x314C: 25, 0x314D: 26, 0x314E: 27
    ]

    // ㅗ+ㅏ=ㅘ ㅗ+ㅐ=ㅙ ㅗ+ㅣ=ㅚ ㅜ+ㅓ=ㅝ ㅜ+ㅔ=ㅞ ㅜ+ㅣ=ㅟ ㅡ+ㅣ=ㅢ
    private let jungCompound: [Int: [Int: Int]] = [
        8: [0: 9, 1: 10, 20: 11],
        13: [4: 14, 5: 15, 20: 16],
        18: [20: 19]
    ]

    // ㄱ+ㅅ=ㄳ ㄴ+ㅈ=ㄵ ㄴ+ㅎ=ㄶ ㄹ+ㄱ=ㄺ ㄹ+ㅁ=ㄻ ㄹ+ㅂ=ㄼ ㄹ+ㅅ=ㄽ
    // ㄹ+ㅌ=ㄾ ㄹ+ㅍ=ㄿ ㄹ+ㅎ=ㅀ ㅂ+ㅅ=ㅄ
    private let jongCompound: [Int: [Int: Int]] = [
        1: [19: 3],
        4: [22: 5, 27: 6],
        8: [1: 9, 16: 10, 17: 11, 19: 12, 25: 13, 26: 14, 27: 15],
        17: [19: 18]
    ]

    // Compound jong → (remaining jong, choseong of moved consonant).
    private let jongSplit: [Int: (Int, Int)] = [
        3: (1, 9), 5: (4, 12), 6: (4, 18), 9: (8, 0), 10: (8, 6),
        11: (8, 7), 12: (8, 9), 13: (8, 16), 14: (8, 17), 15: (8, 18),
        18: (17, 9)
    ]

    // Reverse lookup: which choseong does this jongseong convert to when
    // forming the initial of the next syllable?
    private let jongToCho: [Int: Int] = [
        1: 0, 2: 1, 4: 2, 7: 3, 8: 5, 16: 6, 17: 7, 19: 9, 20: 10, 21: 11,
        22: 12, 23: 14, 24: 15, 25: 16, 26: 17, 27: 18
    ]

    private let compatFromCho: [Int: UInt32] = [
        0: 0x3131, 1: 0x3132, 2: 0x3134, 3: 0x3137, 4: 0x3138, 5: 0x3139,
        6: 0x3141, 7: 0x3142, 8: 0x3143, 9: 0x3145, 10: 0x3146, 11: 0x3147,
        12: 0x3148, 13: 0x3149, 14: 0x314A, 15: 0x314B, 16: 0x314C,
        17: 0x314D, 18: 0x314E
    ]

    private let compatFromJung: [Int: UInt32] = [
        0: 0x314F, 1: 0x3150, 2: 0x3151, 3: 0x3152, 4: 0x3153, 5: 0x3154,
        6: 0x3155, 7: 0x3156, 8: 0x3157, 9: 0x3158, 10: 0x3159, 11: 0x315A,
        12: 0x315B, 13: 0x315C, 14: 0x315D, 15: 0x315E, 16: 0x315F,
        17: 0x3160, 18: 0x3161, 19: 0x3162, 20: 0x3163
    ]

    private let compatFromJong: [Int: UInt32] = [
        1: 0x3131, 2: 0x3132, 3: 0x3133, 4: 0x3134, 5: 0x3135, 6: 0x3136,
        7: 0x3137, 8: 0x3139, 9: 0x313A, 10: 0x313B, 11: 0x313C, 12: 0x313D,
        13: 0x313E, 14: 0x313F, 15: 0x3140, 16: 0x3141, 17: 0x3142, 18: 0x3144,
        19: 0x3145, 20: 0x3146, 21: 0x3147, 22: 0x3148, 23: 0x314A, 24: 0x314B,
        25: 0x314C, 26: 0x314D, 27: 0x314E
    ]
}
#endif
