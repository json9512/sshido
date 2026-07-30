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
        let corpus = join(rows: rows, cols: cols)
        guard !corpus.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        let nsRange = NSRange(corpus.startIndex..., in: corpus)
        let matches = detector.matches(in: corpus, options: [], range: nsRange)

        var seen = Set<String>()
        var out: [DetectedURL] = []
        out.reserveCapacity(matches.count)

        for match in matches {
            guard let range = Range(match.range, in: corpus),
                  let original = match.url
            else { continue }
            let scheme = original.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { continue }

            let raw = String(corpus[range])
            let trimmed = stripTrailingPunctuation(raw)
            guard let cleanURL = URL(string: trimmed) else { continue }
            let key = cleanURL.absoluteString
            guard seen.insert(key).inserted else { continue }
            out.append(DetectedURL(url: cleanURL, raw: trimmed))
        }
        return out
    }

    static func join(rows: [String], cols: Int) -> String {
        guard cols > 0 else { return rows.joined(separator: "\n") }
        var out = ""
        out.reserveCapacity(rows.reduce(0) { $0 + $1.count + 1 })

        for (idx, row) in rows.enumerated() {
            if idx == 0 {
                out.append(row)
                continue
            }
            let prev = rows[idx - 1]
            if let glued = continuation(of: prev, next: row, cols: cols) {
                out.append(glued)
            } else {
                out.append("\n")
                out.append(row)
            }
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
