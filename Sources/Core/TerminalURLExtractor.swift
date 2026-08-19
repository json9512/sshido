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
        return dropContainedFragments(out)
    }

    // A wrapped row that failed to glue still matches alone as a bare domain
    // ("udflarestorage.com/…"); drop it once a longer candidate contains it.
    private static func dropContainedFragments(_ candidates: [DetectedURL]) -> [DetectedURL] {
        candidates.filter { c in
            if c.raw.lowercased().hasPrefix("http") { return true }
            return !candidates.contains { $0.raw.count > c.raw.count && $0.raw.contains(c.raw) }
        }
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

            let raw = extendTruncatedMatch(corpus: corpus, range: range)
            let trimmed = stripTrailingPunctuation(raw)
            guard let cleanURL = URL(string: trimmed) else { continue }
            guard seen.insert(cleanURL.absoluteString).inserted else { continue }
            out.append(DetectedURL(url: cleanURL, raw: trimmed))
        }
    }

    // NSDataDetector silently drops a long URL's query string when unrelated
    // text follows on the same line ("…87f17; echo" matches only to the path).
    private static func extendTruncatedMatch(corpus: String, range: Range<String.Index>) -> String {
        let matched = corpus[range]
        guard matched.lowercased().hasPrefix("http") else { return String(matched) }
        var end = range.upperBound
        while end < corpus.endIndex, urlAllowedTrailing.contains(corpus[end]) {
            end = corpus.index(after: end)
        }
        return String(corpus[range.lowerBound..<end])
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
        for (i, row) in rows.enumerated() {
            if isRuleRow(row) {
                out.append("\n")
                prev = nil
                continue
            }
            if let prev,
               let glued = continuation(
                   of: prev, next: row, cols: cols, inRun: isHardWrapRun(rows, i)
               ) {
                out.append(glued)
            } else {
                if !out.isEmpty { out.append("\n") }
                out.append(row)
            }
            prev = row
        }
        return out
    }

    // A tmux window narrower than the client wraps rows short of `cols`; the real
    // wrap column shows up as adjacent rows sharing one exact width.
    private static func isHardWrapRun(_ rows: [String], _ i: Int) -> Bool {
        let width = rows[i - 1].count
        guard width >= minPaneWidth else { return false }
        if rows[i].count == width { return true }
        return i >= 2 && rows[i - 2].count == width
    }

    // TUI apps (e.g. Claude Code) wrap URLs below full terminal width with a per-row indent.
    private static let wrapSlack = 4

    // How far a row filling a desktop-sized tmux window can fall short of the phone grid.
    private static let narrowWindowSlack = 8

    private static func continuation(
        of prev: String, next: String, cols: Int, inRun: Bool
    ) -> String? {
        guard let last = prev.last, urlAllowedTrailing.contains(last) else { return nil }
        if prev.count >= cols { return next }
        let stripped = next.drop(while: { $0 == " " })
        guard next.count - stripped.count == leadingSpaceCount(of: prev),
              !startsNewURL(stripped),
              leadingURLRunLength(of: stripped) >= 2
        else { return nil }
        if inRun { return String(stripped) }
        if cols > wrapSlack, prev.count >= cols - wrapSlack { return String(stripped) }
        // Two-row hard wrap: no equal-width run proves the wrap column, so
        // demand a URL running off a near-full row onto a purely-URL tail.
        guard prev.count >= max(minPaneWidth, cols - narrowWindowSlack),
              next.count < prev.count,
              urlRunsToRowEnd(prev),
              stripped.allSatisfy({ urlAllowedTrailing.contains($0) }),
              !isStandaloneLink(String(stripped))
        else { return nil }
        return String(stripped)
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // A tail that is a complete link on its own is the next URL, not a wrap remainder.
    private static func isStandaloneLink(_ s: String) -> Bool {
        guard let detector = linkDetector else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return detector.firstMatch(in: s, options: [], range: range).map { $0.range == range } ?? false
    }

    private static func urlRunsToRowEnd(_ row: String) -> Bool {
        guard let r = row.range(of: #"https?://"#, options: [.regularExpression, .caseInsensitive])
        else { return false }
        return row[r.lowerBound...].allSatisfy { urlAllowedTrailing.contains($0) }
    }

    private static func startsNewURL(_ s: some StringProtocol) -> Bool {
        let lowered = s.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
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
