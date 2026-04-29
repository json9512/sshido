import XCTest
@testable import sshidoCore

final class TerminalURLExtractorTests: XCTestCase {
    func testSingleLineURL() {
        let rows = ["Visit https://example.com here"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://example.com")
    }

    func testSoftWrappedURLAcrossRows() {
        let row0 = "See https://very.long"
        XCTAssertEqual(row0.count, 21)
        let cols = 21
        let rows = [row0, "-example.com/path"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: cols)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://very.long-example.com/path")
    }

    func testProseGlueProtection() {
        let rows = ["Click http://example.com", "for more info"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, "http://example.com")
    }

    func testTrailingPunctuationStripped() {
        let rows = ["See https://example.com."]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://example.com")
    }

    func testBalancedParensPreserved() {
        let rows = ["Doc: https://en.wikipedia.org/wiki/Foo_(bar)"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://en.wikipedia.org/wiki/Foo_(bar)")
    }

    func testUnbalancedClosingParenStripped() {
        let rows = ["Read this (https://example.com)"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://example.com")
    }

    func testMultipleURLsInOrder() {
        let rows = [
            "First: https://github.com/foo",
            "Second: http://localhost:5173/cb",
            "Third: https://example.org"
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.map(\.url.absoluteString), [
            "https://github.com/foo",
            "http://localhost:5173/cb",
            "https://example.org"
        ])
    }

    func testLocalhostURLDetected() {
        let rows = ["Callback: http://localhost:5173/cb?code=abc"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, "http://localhost:5173/cb?code=abc")
    }

    func testOAuthAuthorizeURLDetected() {
        let raw = "https://slack.com/oauth/v2_user/authorize?response_type=code&client_id=1601185624273.8899143856786&redirect_uri=http%3A%2F%2Flocalhost%3A3118%2Fcallback&state=abc&scope=chat%3Awrite"
        let urls = TerminalURLExtractor.extract(from: [raw], cols: 4096)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, raw)
    }

    func testNonHTTPSchemesFiltered() {
        let rows = ["Email me@example.com or visit ftp://x.example.com or file:///etc/passwd"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertTrue(urls.isEmpty, "Got unexpected URLs: \(urls.map(\.url.absoluteString))")
    }

    func testDedupedAcrossRepeatedRows() {
        let rows = [
            "https://example.com/foo",
            "noise",
            "https://example.com/foo",
            "https://example.com/foo"
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.url.absoluteString, "https://example.com/foo")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(TerminalURLExtractor.extract(from: [], cols: 80).isEmpty)
        XCTAssertTrue(TerminalURLExtractor.extract(from: ["", "  ", "\t"], cols: 80).isEmpty)
    }

    func testWrappedURLPreservesQueryParams() {
        let row0 = "https://claude.ai/oauth/aut"
        XCTAssertEqual(row0.count, 27)
        let cols = 27
        let row1 = "horize?code=abc&state=xyz"
        XCTAssertLessThan(row1.count, cols)
        let rows = [row0, row1, "$ "]
        let urls = TerminalURLExtractor.extract(from: rows, cols: cols)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(
            urls.first?.url.absoluteString,
            "https://claude.ai/oauth/authorize?code=abc&state=xyz"
        )
    }

    func testStripTrailingPunctuationDirect() {
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com."), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com,"), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com)"), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://en.wikipedia.org/wiki/Foo_(bar)"), "https://en.wikipedia.org/wiki/Foo_(bar)")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com).,"), "https://example.com")
    }
}
