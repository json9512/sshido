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

    func testClaudeCodeMCPAuthScreenAt60Cols() {
        let rows = [
            "",
            " If your browser doesn't open automatically, copy(c to",
            " this URL manually                               copy)",
            "",
            " https://mcp.linear.app/authorize?response_type=code&client",
            " _id=https%3A%2F%2Fclaude.ai%2Foauth%2Fclaude-code-client-m",
            " etadata&code_challenge=Idv9dENGgpN-R6h5f4MUd2pDZSNwDGxOs7B",
            " 66njmiB4&code_challenge_method=S256&redirect_uri=http%3A%2",
            " F%2Flocalhost%3A56177%2Fcallback&state=b9k17BWJoOZ7s57Mokw",
            " QGkNg6tDdkYsyKlh8AYhHqpE&scope=read+write&resource=https%3",
            " A%2F%2Fmcp.linear.app%2Fmcp",
            "",
            "",
            " If the redirect page shows a connection error, paste the",
            " URL from your browser's address bar:",
            " URL >"
        ]
        let expected = "https://mcp.linear.app/authorize?response_type=code&client_id=https%3A%2F%2Fclaude.ai%2Foauth%2Fclaude-code-client-metadata&code_challenge=Idv9dENGgpN-R6h5f4MUd2pDZSNwDGxOs7B66njmiB4&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A56177%2Fcallback&state=b9k17BWJoOZ7s57MokwQGkNg6tDdkYsyKlh8AYhHqpE&scope=read+write&resource=https%3A%2F%2Fmcp.linear.app%2Fmcp"
        let urls = TerminalURLExtractor.extract(from: rows, cols: 60)
        XCTAssertEqual(urls.map(\.url.absoluteString), [expected])
        XCTAssertEqual(OAuthURLDetector.detect(expected)?.port, 56177)
    }

    func testClaudeCodeMCPAuthScreenAt80Cols() {
        let rows = [
            "",
            " If your browser doesn't open automatically, copy this URL manually (c to copy)",
            " https://mcp.linear.app/authorize?response_type=code&client_id=https%3A%2F%2Fcl",
            " aude.ai%2Foauth%2Fclaude-code-client-metadata&code_challenge=v7akWcP3OJqaXZ5Ks",
            " uf0ZUKOAUGeSlgBWI1t5SPgl4Q&code_challenge_method=S256&redirect_uri=http%3A%2F%",
            " 2Flocalhost%3A49379%2Fcallback&state=nlcJnd_bhzuCajmAoppzpzWaW-k8E7ieWzXad17X2",
            " Jw&scope=read+write&resource=https%3A%2F%2Fmcp.linear.app%2Fmcp",
            ""
        ]
        let expected = "https://mcp.linear.app/authorize?response_type=code&client_id=https%3A%2F%2Fclaude.ai%2Foauth%2Fclaude-code-client-metadata&code_challenge=v7akWcP3OJqaXZ5Ksuf0ZUKOAUGeSlgBWI1t5SPgl4Q&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A49379%2Fcallback&state=nlcJnd_bhzuCajmAoppzpzWaW-k8E7ieWzXad17X2Jw&scope=read+write&resource=https%3A%2F%2Fmcp.linear.app%2Fmcp"
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.map(\.url.absoluteString), [expected])
        XCTAssertEqual(OAuthURLDetector.detect(expected)?.port, 49379)
    }

    func testShellPromptAfterNearFullURLRowNotGlued() {
        let row0 = "https://claude.ai/oauth/aut"
        let row1 = "horize?code=abc&state=xyz"
        let urls = TerminalURLExtractor.extract(from: [row0, row1, "% "], cols: 27)
        XCTAssertEqual(
            urls.map(\.url.absoluteString),
            ["https://claude.ai/oauth/authorize?code=abc&state=xyz"]
        )
    }

    func testIndentMismatchNotGlued() {
        let rows = [
            "  https://example.com/aaaaaa",
            "bbbb more"
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 30)
        XCTAssertEqual(urls.map(\.url.absoluteString), ["https://example.com/aaaaaa"])
    }

    func testHardWrapNarrowerThanClientCols() {
        let wrapped = [
            "https://cc0d4607c5e8b2c1cab18a539969d3d2.r2.clo",
            "udflarestorage.com/yojeong/households/6d87135f-",
            "1d11-4321-b8cf-de59d51ff5f3/devices/621c186f-57",
            "47-405e-8cd2-44f45733b44c/2026/08/06/clip-17860",
            "03488600.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X",
            "-Amz-Credential=f6b1b967740f58980a0b9cdf65c1c82",
            "5%2F20260806%2Fauto%2Fs3%2Faws4_request&X-Amz-D",
            "ate=20260806T080530Z&X-Amz-Expires=14400&X-Amz-",
            "SignedHeaders=host&X-Amz-Signature=a94428767b34",
            "5c8474b01ace8a1ae33c297aeb41dd10d20aaa07ba24502",
            "87f17",
        ]
        for w in wrapped.dropLast() { XCTAssertEqual(w.count, 47) }
        let rows = ["클립 링크 (폰에서 바로 열립니다)", ""] + wrapped + ["", "오늘 21:05 KST까지 유효합니다"]
        for cols in [47, 49, 54, 80] {
            let urls = TerminalURLExtractor.extract(from: rows, cols: cols)
            XCTAssertEqual(urls.map(\.raw), [wrapped.joined()], "cols=\(cols)")
        }
    }

    func testEqualLengthRepeatedURLRowsNotGlued() {
        let rows = [
            "https://example.com/foo",
            "https://example.com/bar",
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.map(\.url.absoluteString), [
            "https://example.com/foo",
            "https://example.com/bar",
        ])
    }

    private static let r2URL = "https://cc0d4607c5e8b2c1cab18a539969d3d2.r2.cloudflarestorage.com/yojeong/households/6d87135f-1d11-4321-b8cf-de59d51ff5f3/devices/621c186f-5747-405e-8cd2-44f45733b44c/2026/08/06/clip-1786003488600.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=f6b1b967740f58980a0b9cdf65c1c825%2F20260806%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20260806T080530Z&X-Amz-Expires=14400&X-Amz-SignedHeaders=host&X-Amz-Signature=a94428767b345c8474b01ace8a1ae33c297aeb41dd10d20aaa07ba2450287f17"

    private static func hardWrap(_ text: String, width: Int, indent: String = "") -> [String] {
        var rows: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let chunk = rest.prefix(width - indent.count)
            rows.append(indent + chunk)
            rest = rest.dropFirst(chunk.count)
        }
        return rows
    }

    /// Claude Code wraps long URLs with a two-space hanging indent inside a
    /// tmux window narrower than the client grid; no border column exists to
    /// shrink cols down to the window width (captured from a real 47-col
    /// window on a 52-col client).
    func testIndentedHardWrapRunNarrowerThanClientCols() {
        let rows = ["❯ Reply with these lines:", ""]
            + Self.hardWrap(Self.r2URL, width: 46, indent: "  ")
            + ["", "  https://claude.ai/public/artifacts/0198c9c2", "  -ab12-7cc0-9f6d-1234567890ab"]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 52)
        XCTAssertEqual(urls.map(\.raw), [
            Self.r2URL,
            "https://claude.ai/public/artifacts/0198c9c2-ab12-7cc0-9f6d-1234567890ab",
        ])
    }

    /// A URL short enough to wrap onto only two rows never forms an
    /// equal-width run, so the pair needs its own evidence-based glue.
    func testTwoRowHardWrapNarrowerThanClientCols() {
        let rows = [
            "Artifact published (open on your phone):",
            "  https://claude.ai/public/artifacts/0198c9c2-ab",
            "  -12-7cc0-9f6d-1234567890ab",
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 52)
        XCTAssertEqual(urls.map(\.raw), [
            "https://claude.ai/public/artifacts/0198c9c2-ab-12-7cc0-9f6d-1234567890ab",
        ])
    }

    /// NSDataDetector drops the entire query string when unrelated text
    /// follows the URL on the same corpus line (an echoed shell command,
    /// a full-width row glued to the next text row).
    func testDetectorQueryTruncationRepaired() {
        var rows = Self.hardWrap(Self.r2URL + "; echo", width: 52)
        rows.append("done")
        let urls = TerminalURLExtractor.extract(from: rows, cols: 52)
        XCTAssertEqual(urls.map(\.raw), [Self.r2URL])
    }

    /// When glue legitimately fails, a wrapped row still matches on its own
    /// as a bare domain; such fragments are noise once the full URL is found.
    func testSchemelessFragmentOfLongerURLDropped() {
        let rows = [
            "  x https://long.example.com/path/abcdef",
            "long.example.com/path/abc",
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.map(\.url.absoluteString), ["https://long.example.com/path/abcdef"])
    }

    func testStandaloneBareDomainAfterURLRowNotGlued() {
        let rows = [
            "see https://foo.example.com/aaaa",
            "other.example.com/bbb",
        ]
        let urls = TerminalURLExtractor.extract(from: rows, cols: 80)
        XCTAssertEqual(urls.map(\.raw), [
            "https://foo.example.com/aaaa",
            "other.example.com/bbb",
        ])
    }

    func testStripTrailingPunctuationDirect() {
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com."), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com,"), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com)"), "https://example.com")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://en.wikipedia.org/wiki/Foo_(bar)"), "https://en.wikipedia.org/wiki/Foo_(bar)")
        XCTAssertEqual(TerminalURLExtractor.stripTrailingPunctuation("https://example.com).,"), "https://example.com")
    }
}
