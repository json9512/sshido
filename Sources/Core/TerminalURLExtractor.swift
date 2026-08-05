import Foundation

public struct DetectedURL: Hashable, Sendable, Identifiable {
    public let url: URL
    public let raw: String
    public var id: String { raw }

    public init(url: URL, raw: String) {
        self.url = url
        self.raw = raw
    }
}

public enum TerminalURLExtractor {
    public static func extract(from rows: [String], cols: Int) -> [DetectedURL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        var seen = Set<String>()
        var out: [DetectedURL] = []
        // Each pane wraps at its own width, so a corpus built from whole rows splices
        // the neighbouring pane into the middle of every wrapped URL.
        for pane in paneColumnRanges(rows: rows, cols: cols) {
            let paneRows = rows.map { columns(of: $0, in: pane) }
            collect(from: join(rows: paneRows, cols: pane.count),
                    detector: detector, seen: &seen, into: &out)
        }
        return out
    }

    private static func collect(
        from corpus: String,
        detector: NSDataDetector,
        seen: inout Set<String>,
        into out: inout [DetectedURL]
    ) {
        guard !corpus.isEmpty else { return }
        let nsRange = NSRange(corpus.startIndex..., in: corpus)
        for match in detector.matches(in: corpus, options: [], range: nsRange) {
            guard let range = Range(match.range, in: corpus),
                  let original = match.url
            else { continue }
            let scheme = original.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { continue }

            let raw = String(corpus[range])
            let trimmed = stripTrailingPunctuation(raw)
            guard let cleanURL = URL(string: trimmed) else { continue }
            guard seen.insert(cleanURL.absoluteString).inserted else { continue }
            out.append(DetectedURL(url: cleanURL, raw: trimmed))
        }
    }

    static let minPaneWidth = 8

    static func paneColumnRanges(rows: [String], cols: Int) -> [Range<Int>] {
        let width = cols > 0 ? cols : (rows.map(\.count).max() ?? 0)
        guard width > 0 else { return [] }
        let borders = verticalBorderColumns(rows: rows, width: width)
        guard !borders.isEmpty else { return [0..<width] }

        var ranges: [Range<Int>] = []
        var start = 0
        for column in borders.sorted() {
            if column > start { ranges.append(start..<column) }
            start = column + 1
        }
        if start < width { ranges.append(start..<width) }
        let usable = ranges.filter { $0.count >= minPaneWidth }
        return usable.isEmpty ? [0..<width] : usable
    }

    private static func verticalBorderColumns(rows: [String], width: Int) -> [Int] {
        guard rows.count >= 3 else { return [] }
        let grid = rows.map(Array.init)
        var out: [Int] = []
        for column in 0..<width {
            var covering = 0
            var border = 0
            for row in grid where row.count > column {
                covering += 1
                if verticalBorderChars.contains(row[column]) { border += 1 }
            }
            if covering >= 3 && border * 5 >= covering * 3 { out.append(column) }
        }
        return out
    }

    private static func columns(of row: String, in range: Range<Int>) -> String {
        let chars = Array(row)
        guard range.lowerBound < chars.count else { return "" }
        let upper = min(range.upperBound, chars.count)
        return rightTrim(String(chars[range.lowerBound..<upper]))
    }

    private static func rightTrim(_ s: String) -> String {
        String(s.reversed().drop(while: { $0 == " " }).reversed())
    }

    // A pane border or a TUI box lid: gluing a URL across it would swallow the rule.
    static func isRuleRow(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return false }
        return trimmed.allSatisfy { horizontalBorderChars.contains($0) }
    }

    private static let verticalBorderChars: Set<Character> = [
        "\u{2502}", "\u{2503}", "\u{2506}", "\u{2507}", "\u{250A}", "\u{250B}", "\u{2551}",
    ]

    private static let horizontalBorderChars: Set<Character> = [
        "\u{2500}", "\u{2501}", "\u{2504}", "\u{2505}", "\u{2508}", "\u{2509}", "\u{2550}",
        "-", "=", "_", "\u{2014}", "\u{2013}",
    ]

    static func join(rows: [String], cols: Int) -> String {
        guard cols > 0 else { return rows.joined(separator: "\n") }
        var out = ""
        out.reserveCapacity(rows.reduce(0) { $0 + $1.count + 1 })

        var prev: String?
        for row in rows {
            if isRuleRow(row) {
                out.append("\n")
                prev = nil
                continue
            }
            if let prev, let glued = continuation(of: prev, next: row, cols: cols) {
                out.append(glued)
            } else {
                if !out.isEmpty { out.append("\n") }
                out.append(row)
            }
            prev = row
        }
        return out
    }

    // TUI apps (e.g. Claude Code) wrap URLs below full terminal width with a per-row indent.
    private static let wrapSlack = 4

    private static func continuation(of prev: String, next: String, cols: Int) -> String? {
        guard let last = prev.last, urlAllowedTrailing.contains(last) else { return nil }
        if prev.count >= cols { return next }
        guard cols > wrapSlack, prev.count >= cols - wrapSlack else { return nil }
        let stripped = next.drop(while: { $0 == " " })
        let nextIndent = next.count - stripped.count
        guard nextIndent == leadingSpaceCount(of: prev),
              leadingURLRunLength(of: stripped) >= 2
        else { return nil }
        return String(stripped)
    }

    private static func leadingSpaceCount(of s: String) -> Int {
        s.prefix(while: { $0 == " " }).count
    }

    private static func leadingURLRunLength(of s: Substring) -> Int {
        s.prefix(while: { urlAllowedTrailing.contains($0) }).count
    }

    private static let urlAllowedTrailing: Set<Character> = {
        var s = Set<Character>()
        for u in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%" {
            s.insert(u)
        }
        return s
    }()

    static func stripTrailingPunctuation(_ raw: String) -> String {
        var s = Substring(raw)
        let trimmable: Set<Character> = [".", ",", ";", ":", "!", "?", "'", "\"", ">"]
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]

        while let last = s.last {
            if trimmable.contains(last) {
                s = s.dropLast()
                continue
            }
            if let opener = pairs[last] {
                let opens = s.filter { $0 == opener }.count
                let closes = s.filter { $0 == last }.count
                if closes > opens {
                    s = s.dropLast()
                    continue
                }
            }
            break
        }
        return String(s)
    }
}
