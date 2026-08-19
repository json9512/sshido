import XCTest
@testable import sshidoCore

final class BrowserURLResolverTests: XCTestCase {
    func testPublicURLOpensDirectly() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("https://example.com/path?q=1"),
            .direct(URL(string: "https://example.com/path?q=1")!)
        )
    }

    func testSchemelessPublicURLDefaultsToHTTPS() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("example.com/docs"),
            .direct(URL(string: "https://example.com/docs")!)
        )
    }

    func testLocalhostIsTunneled() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://localhost:5173/app"),
            .tunneled(open: URL(string: "http://127.0.0.1:5173/app")!, remoteHost: "127.0.0.1", port: 5173)
        )
    }

    func testLoopbackWithoutPortUsesSchemeDefault() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://127.0.0.1/status"),
            .tunneled(open: URL(string: "http://127.0.0.1:80/status")!, remoteHost: "127.0.0.1", port: 80)
        )
    }

    func testPrivateIPIsTunneledToThatHost() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://192.168.219.103:8123/lovelace"),
            .tunneled(open: URL(string: "http://127.0.0.1:8123/lovelace")!, remoteHost: "192.168.219.103", port: 8123)
        )
    }

    func testDotLocalHostnameIsTunneled() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://homepi.local:3000/"),
            .tunneled(open: URL(string: "http://127.0.0.1:3000/")!, remoteHost: "homepi.local", port: 3000)
        )
    }

    func testCarrierGradeAndPublicIPNotTunneled() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://8.8.8.8/x"),
            .direct(URL(string: "http://8.8.8.8/x")!)
        )
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://172.32.0.1/x"),
            .direct(URL(string: "http://172.32.0.1/x")!)
        )
    }

    func testTenAndOneSevenTwoRangesTunneled() {
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://10.0.0.7:9090"),
            .tunneled(open: URL(string: "http://127.0.0.1:9090")!, remoteHost: "10.0.0.7", port: 9090)
        )
        XCTAssertEqual(
            BrowserURLResolver.resolve("http://172.20.1.2:80/x"),
            .tunneled(open: URL(string: "http://127.0.0.1:80/x")!, remoteHost: "172.20.1.2", port: 80)
        )
    }

    func testNonHTTPSchemeRejected() {
        XCTAssertNil(BrowserURLResolver.resolve("ftp://example.com/file"))
        XCTAssertNil(BrowserURLResolver.resolve(""))
    }
}
