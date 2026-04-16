#if canImport(UIKit)
import UIKit
import QuartzCore
import SwiftTerm
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
public final class MetalTerminalView: UIView, UIKeyInput, UITextInputTraits {
    public let renderer: MetalTerminalRenderer
    public weak var bridge: MetalTerminalBridge?

    public var autocorrectionType: UITextAutocorrectionType = .no
    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var keyboardAppearance: UIKeyboardAppearance = .dark
    public var returnKeyType: UIReturnKeyType = .default

    private var pinchBaseFontSize: CGFloat = 16
    private var keyboardOverlap: CGFloat = 0
    private var lastLayoutSize: CGSize = .zero

    public init(renderer: MetalTerminalRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(renderer.metalLayer)
        renderer.metalLayer.frame = bounds

        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
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
    public var hasText: Bool { true }
    public override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }

    public func insertText(_ text: String) {
        deleteRepeatCount = 0
        if text == "\n" || text == "\r" || text == "\r\n" {
            bridge?.sendBytes([0x0d])
            return
        }
        bridge?.sendBytes(Array(text.utf8))
    }

    private var lastDeleteAt: CFTimeInterval = 0
    private var deleteRepeatCount: Int = 0

    public func deleteBackward() {
        let now = CACurrentMediaTime()
        if now - lastDeleteAt < 0.4 {
            deleteRepeatCount = min(deleteRepeatCount + 1, 20)
        } else {
            deleteRepeatCount = 0
        }
        lastDeleteAt = now
        let n: Int
        switch deleteRepeatCount {
        case 0: n = 1
        case 1: n = 1
        case 2: n = 2
        case 3: n = 3
        case 4: n = 5
        case 5: n = 8
        default: n = 12
        }
        bridge?.sendBytes(Array(repeating: 0x7f, count: n))
    }

    public override var keyCommands: [UIKeyCommand]? {
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
            UIKeyCommand(input: "l", modifierFlags: .control, action: #selector(kCtrlL))
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

    private var panAccum: CGFloat = 0
    @objc private func didPan(_ g: UIPanGestureRecognizer) {
        let cellH = renderer.glyphMetrics.cellHeight
        switch g.state {
        case .began:
            panAccum = 0
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
        if bridge.terminal.isCurrentBufferAlternate {
            let button = lines > 0 ? 64 : 65
            let col = max(1, bridge.terminal.cols / 2)
            let row = max(1, bridge.terminal.rows / 2)
            let seq = "\u{1b}[<\(button);\(col);\(row)M"
            let bytes = Array(seq.utf8)
            let reps = min(max(abs(lines) / 2, 1), 6)
            for _ in 0..<reps { bridge.sendBytes(bytes) }
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
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }
        selectionStart = nil
        selectionEnd = nil
        renderer.setNeedsRender()
    }

    private var selectionStart: (col: Int, row: Int)?
    private var selectionEnd: (col: Int, row: Int)?

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
        renderer.metalLayer.frame = f
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
#endif
