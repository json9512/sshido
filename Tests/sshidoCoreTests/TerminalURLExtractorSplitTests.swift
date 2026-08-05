import XCTest
@testable import sshidoCore

/// Screens laid out like a tmux vertical split: every row carries both panes,
/// separated by a box-drawing border.
final class TerminalURLExtractorSplitTests: XCTestCase {
    private let leftWidth = 24
    private let rightWidth = 24
    private var cols: Int { leftWidth + 1 + rightWidth }

    private func split(_ left: String, _ right: String) -> String {
        let l = left.count > leftWidth ? String(left.prefix(leftWidth)) : left
        return l.padding(toLength: leftWidth, withPad: " ", startingAt: 0) + "\u{2502}" + right
    }

    private func awsScreen() -> [String] {
        [
            split("times out. With no", "~ > aws login"),
            split("real source video the", "Attempting to open your"),
            split("concat fails, which", "default browser. If the"),
            split("triggers the fallback", "browser does not open, o"),
            split("release - a few", "pen the following URL."),
            split("minutes, and I'll", ""),
            split("drive the dispatcher", "https://ap-northeast-2.s"),
            split("rather than wait on", "ignin.aws.amazon.com/v1/"),
            split("its schedule.", "authorize?response_type="),
            split("- The alimtalk needs", "code&client_id=arn%3Aaws"),
            split("elder_name on the", "%3Asignin%3A%3A%3Adevtoo"),
            split("household.", "ls%2Fsame-device&state=b"),
            split("sendAlimtalk skips", "43ac0b9-9579-40ec-826f-7"),
        ]
    }

    func testWrappedURLInRightPaneIsReassembled() {
        let urls = TerminalURLExtractor.extract(from: awsScreen(), cols: cols)
        let joined = urls.map(\.url.absoluteString)
        XCTAssertEqual(
            joined,
            ["https://ap-northeast-2.signin.aws.amazon.com/v1/authorize?response_type=code&client_id=arn%3Aaws%3Asignin%3A%3A%3Adevtools%2Fsame-device&state=b43ac0b9-9579-40ec-826f-7"],
            "wrapped URL inside a split pane must come back whole, not as row fragments"
        )
    }

    func testLeftPaneTextNeverLandsInsideAURL() {
        let urls = TerminalURLExtractor.extract(from: awsScreen(), cols: cols)
        for u in urls {
            XCTAssertFalse(u.raw.contains("alimtalk"), "left pane bled into: \(u.raw)")
            XCTAssertFalse(u.raw.contains("household"), "left pane bled into: \(u.raw)")
            XCTAssertFalse(u.raw.contains("\u{2502}"), "border bled into: \(u.raw)")
        }
    }

    func testURLsInBothPanesAreFound() {
        let rows = [
            split("logs at", "docs at"),
            split("https://left.example.co", "https://right.example.co"),
            split("m/alpha", "m/beta"),
        ]
        let found = Set(TerminalURLExtractor.extract(from: rows, cols: cols).map(\.url.absoluteString))
        XCTAssertEqual(found, ["https://left.example.com/alpha", "https://right.example.com/beta"])
    }

    func testHorizontalBorderDoesNotGlueAcrossPanes() {
        let rows = [
            "https://example.com/very/long/path/that/",
            String(repeating: "\u{2500}", count: 40),
            "fills-the-row-completely-and-then-some!!",
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 40)
        XCTAssertEqual(urls.map(\.url.absoluteString), ["https://example.com/very/long/path/that/"])
    }

    func testUnsplitScreenStillJoinsWrappedURL() {
        let row0 = "https://example.com/aaaaaaaaaaaaaaaaaaaa"
        XCTAssertEqual(row0.count, 40)
        let urls = TerminalURLExtractor.extract(from: [row0, "bbbb/end"], cols: 40)
        XCTAssertEqual(urls.map(\.url.absoluteString), ["https://example.com/aaaaaaaaaaaaaaaaaaaabbbb/end"])
    }
}
