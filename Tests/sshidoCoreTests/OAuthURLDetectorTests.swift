import XCTest
@testable import sshidoCore

final class OAuthURLDetectorTests: XCTestCase {
    func testSentryAuthorizeURLIsDetected() {
        let url = "https://mcp.sentry.dev/oauth/authorize?response_type=code&client_id=abc&code_challenge=xyz&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A57733%2Fcallback&state=qq&scope=org%3Aread"
        let target = OAuthURLDetector.detect(url)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.port, 57733)
        XCTAssertEqual(target?.originalURL.absoluteString, url)
    }

    func testLoopbackIPv4Detected() {
        let url = "https://example.com/oauth/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcb"
        XCTAssertEqual(OAuthURLDetector.detect(url)?.port, 8765)
    }

    func testNonLocalhostRedirectIgnored() {
        let url = "https://example.com/oauth/authorize?redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb"
        XCTAssertNil(OAuthURLDetector.detect(url))
    }

    func testHttpsLocalhostIgnored() {
        let url = "https://example.com/oauth/authorize?redirect_uri=https%3A%2F%2Flocalhost%3A443%2Fcb"
        XCTAssertNil(OAuthURLDetector.detect(url))
    }

    func testRedirectWithoutPortIgnored() {
        let url = "https://example.com/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%2Fcb"
        XCTAssertNil(OAuthURLDetector.detect(url))
    }

    func testURLWithoutRedirectUriIgnored() {
        let url = "https://example.com/some/page?foo=bar"
        XCTAssertNil(OAuthURLDetector.detect(url))
    }

    func testEmptyStringIgnored() {
        XCTAssertNil(OAuthURLDetector.detect(""))
        XCTAssertNil(OAuthURLDetector.detect("   "))
    }

    func testNonHttpSchemeIgnored() {
        XCTAssertNil(OAuthURLDetector.detect("ftp://example.com/?redirect_uri=http%3A%2F%2Flocalhost%3A80%2Fcb"))
    }

    func testWhitespaceIsTrimmed() {
        let url = "  https://example.com/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A1234%2Fcb  \n"
        XCTAssertEqual(OAuthURLDetector.detect(url)?.port, 1234)
    }

    func testSlackAuthorizeURL() {
        let url = "https://slack.com/oauth/v2_user/authorize?response_type=code&client_id=1601185624273.8899143856786&code_challenge=uBixLgb3S8tlhlijxjKMM6ZDIMLe9RYttr36KR2ofXY&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A3118%2Fcallback&state=AtLQFDQL-TeHdk8RJ8pW8DCvc0UAw4VjH2SfBbIdu-8&scope=search%3Aread.public+search%3Aread.private+search%3Aread.mpim+search%3Aread.im+search%3Aread.files+search%3Aread.users+chat%3Awrite+channels%3Ahistory+groups%3Ahistory+mpim%3Ahistory+im%3Ahistory+canvases%3Aread+canvases%3Awrite+users%3Aread+users%3Aread.email&resource=https%3A%2F%2Fmcp.slack.com%2F"
        XCTAssertEqual(OAuthURLDetector.detect(url)?.port, 3118)
    }

    func testParseRedirectURIDirectly() {
        XCTAssertEqual(OAuthURLDetector.parseRedirectURI("http://localhost:57733/callback"), 57733)
        XCTAssertEqual(OAuthURLDetector.parseRedirectURI("http://127.0.0.1:9000/"), 9000)
        XCTAssertNil(OAuthURLDetector.parseRedirectURI("http://example.com:57733/callback"))
        XCTAssertNil(OAuthURLDetector.parseRedirectURI("https://localhost:57733/callback"))
    }
}
