import XCTest
@testable import sshidoCore

final class WheelEchoDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPayloadMatchesSwiftTermSGREncoding() {
        XCTAssertEqual(WheelEchoDetector.payload(button: 65, col: 38, row: 21), "65;39;22M")
        XCTAssertEqual(WheelEchoDetector.payload(button: 64, col: 0, row: 0), "64;1;1M")
    }

    func testTripsWhenSentPayloadAppearsOnScreen() {
        var d = WheelEchoDetector()
        d.recordSent("65;39;22M", at: t0)
        XCTAssertTrue(d.isWatching(at: t0))
        XCTAssertTrue(d.tripped(by: "~ ❯ 65;39;22M65;39;22M", at: t0.addingTimeInterval(0.2)))
    }

    func testDoesNotTripOnUnrelatedOutput() {
        var d = WheelEchoDetector()
        d.recordSent("65;39;22M", at: t0)
        XCTAssertFalse(d.tripped(by: "build 42 uploaded 2026-08-14", at: t0.addingTimeInterval(0.2)))
        XCTAssertFalse(d.tripped(by: "65;39;23M", at: t0.addingTimeInterval(0.3)))
    }

    func testPayloadExpiresAfterTTL() {
        var d = WheelEchoDetector()
        d.recordSent("65;39;22M", at: t0)
        let late = t0.addingTimeInterval(WheelEchoDetector.payloadTTL + 0.1)
        XCTAssertFalse(d.isWatching(at: late))
        XCTAssertFalse(d.tripped(by: "65;39;22M", at: late))
    }

    func testTripClearsAllPayloads() {
        var d = WheelEchoDetector()
        d.recordSent("65;39;22M", at: t0)
        d.recordSent("64;39;22M", at: t0)
        XCTAssertTrue(d.tripped(by: "x65;39;22Mx", at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(d.tripped(by: "x64;39;22Mx", at: t0.addingTimeInterval(0.2)))
        XCTAssertFalse(d.isWatching(at: t0.addingTimeInterval(0.2)))
    }

    func testRepeatedSendsDeduplicate() {
        var d = WheelEchoDetector()
        for _ in 0..<10 { d.recordSent("65;39;22M", at: t0) }
        XCTAssertTrue(d.isWatching(at: t0))
        XCTAssertTrue(d.tripped(by: "65;39;22M", at: t0.addingTimeInterval(0.1)))
    }
}
