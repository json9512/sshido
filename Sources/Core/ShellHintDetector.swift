import Foundation

public struct StyledCell: Equatable, Sendable {
    public static let defaultStyle = 0

    public let character: Character
    public let style: Int

    public init(character: Character, style: Int) {
        self.character = character
        self.style = style
    }
}

public struct DetectedShellHint: Hashable, Sendable, Identifiable {
    public let command: String
    public var id: String { command }
    public var promptInput: String { "! " + command }

    public init(command: String) {
        self.command = command
    }
}

public enum ShellHintDetector {
    public static func detect(in rows: [[StyledCell]], cols: Int) -> [DetectedShellHint] {
        let plain = rows.map { String($0.map(\.character)) }
        let commands = TerminalURLExtractor.paneColumnRanges(rows: plain, cols: cols).flatMap { pane in
            commands(in: rows.map { slice($0, to: pane) }, width: pane.count)
        }
        return unique(commands).map(DetectedShellHint.init)
    }

    private struct Segment {
        let style: Int
        let text: String
        let isLast: Bool

        var isBlank: Bool { text.allSatisfy { $0 == " " } }
    }

    private struct Open {
        let style: Int
        let text: String
        let rowWasFull: Bool
    }

    private struct Scan {
        let open: Open?
        let found: [String]

        func closed() -> Scan {
            guard let open else { return self }
            return Scan(open: nil, found: found + [open.text])
        }
    }

    private static let ignoredCommands: Set<String> = ["for shell mode"]

    private static func commands(in rows: [[StyledCell]], width: Int) -> [String] {
        let scan = rows.reduce(Scan(open: nil, found: [])) { scan, row in
            let rowIsFull = row.count == width
            let (resumed, rest) = resume(scan, segments: segments(of: row), rowIsFull: rowIsFull)
            return begin(resumed, segments: rest, rowIsFull: rowIsFull)
        }
        return scan.closed().found.compactMap(command(from:))
    }

    private static func resume(_ scan: Scan, segments: [Segment], rowIsFull: Bool) -> (Scan, [Segment]) {
        guard let open = scan.open else { return (scan, segments) }
        let content = Array(segments.drop(while: \.isBlank))
        guard let head = content.first, head.style == open.style, !startsHint(head.text) else {
            return (scan.closed(), segments)
        }
        let joined = glue(open, head.text)
        let rest = Array(content.dropFirst())
        guard head.isLast else {
            return (Scan(open: nil, found: scan.found + [joined]), rest)
        }
        return (Scan(open: Open(style: open.style, text: joined, rowWasFull: rowIsFull), found: scan.found), rest)
    }

    private static func begin(_ scan: Scan, segments: [Segment], rowIsFull: Bool) -> Scan {
        segments.reduce(scan) { acc, segment in
            guard segment.style != StyledCell.defaultStyle, startsHint(segment.text) else { return acc }
            guard segment.isLast else {
                return Scan(open: acc.open, found: acc.found + [segment.text])
            }
            return Scan(open: Open(style: segment.style, text: segment.text, rowWasFull: rowIsFull), found: acc.found)
        }
    }

    private static func glue(_ open: Open, _ piece: String) -> String {
        if open.rowWasFull { return open.text + piece }
        return trimmed(open.text) + " " + trimmed(piece)
    }

    private static func startsHint(_ text: String) -> Bool {
        let body = trimmed(text)
        return body == "!" || body.hasPrefix("! ")
    }

    private static func command(from text: String) -> String? {
        let body = trimmed(String(trimmed(text).dropFirst()))
        guard !body.isEmpty, !ignoredCommands.contains(body) else { return nil }
        return body
    }

    private static func segments(of row: [StyledCell]) -> [Segment] {
        let chunks = row.reduce([[StyledCell]]()) { chunks, cell in
            guard let last = chunks.last, last[0].style == cell.style else { return chunks + [[cell]] }
            return chunks.dropLast() + [last + [cell]]
        }
        return chunks.enumerated().map { index, chunk in
            Segment(style: chunk[0].style,
                    text: String(chunk.map(\.character)),
                    isLast: index == chunks.count - 1)
        }
    }

    private static func slice(_ row: [StyledCell], to pane: Range<Int>) -> [StyledCell] {
        guard pane.lowerBound < row.count else { return [] }
        let cells = Array(row[pane.lowerBound..<min(pane.upperBound, row.count)])
        return Array(cells.reversed().drop(while: { $0.character == " " }).reversed())
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private static func unique(_ commands: [String]) -> [String] {
        commands.reduce([String]()) { $0.contains($1) ? $0 : $0 + [$1] }
    }
}
