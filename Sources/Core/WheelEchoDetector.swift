import Foundation

/// Wheel reports nobody consumes come back as keyboard echo. Watching the rendered
/// screen for payloads just sent catches the layers a pane probe cannot see: nested
/// connections, pre-attach login shells, foreground processes with arbitrary names.
public struct WheelEchoDetector: Sendable {
    public static let payloadTTL: TimeInterval = 3

    private var sent: [(payload: String, at: Date)] = []

    public init() {}

    /// SwiftTerm's SGR encoding minus the `ESC[<` prefix, which shells swallow
    /// while echoing the printable remainder.
    public static func payload(button: Int, col: Int, row: Int) -> String {
        "\(button);\(col + 1);\(row + 1)M"
    }

    public mutating func recordSent(_ payload: String, at now: Date = Date()) {
        prune(now)
        guard !sent.contains(where: { $0.payload == payload }) else { return }
        sent.append((payload, at: now))
    }

    public mutating func isWatching(at now: Date = Date()) -> Bool {
        prune(now)
        return !sent.isEmpty
    }

    public mutating func tripped(by screenText: String, at now: Date = Date()) -> Bool {
        prune(now)
        guard sent.contains(where: { screenText.contains($0.payload) }) else { return false }
        sent.removeAll()
        return true
    }

    private mutating func prune(_ now: Date) {
        sent.removeAll { now.timeIntervalSince($0.at) > Self.payloadTTL }
    }
}
