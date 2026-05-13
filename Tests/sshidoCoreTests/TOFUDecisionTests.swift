import XCTest
@testable import sshidoCore
@testable import sshidoModels

final class TOFUDecisionTests: XCTestCase {
    func testKnownAndMatching_Accepts() async {
        let known = KnownHost(host: "h", port: 22, fingerprint: "SHA256:match")
        let outcome = await TOFUDecision.decide(
            host: "h", port: 22, presented: "SHA256:match", known: known,
            userDecision: { _ in XCTFail("user should not be asked when fingerprint matches"); return .reject }
        )
        XCTAssertEqual(outcome, .accept(.alreadyKnown))
    }

    func testKnownAndMismatch_UserTrusts_AcceptsAsReplaced() async {
        let known = KnownHost(host: "h", port: 22, fingerprint: "SHA256:old")
        let outcome = await TOFUDecision.decide(
            host: "h", port: 22, presented: "SHA256:new", known: known,
            userDecision: { challenge in
                if case .mismatch(_, _, let expected, let presented) = challenge {
                    XCTAssertEqual(expected, "SHA256:old")
                    XCTAssertEqual(presented, "SHA256:new")
                } else {
                    XCTFail("expected mismatch challenge")
                }
                return .trust
            }
        )
        XCTAssertEqual(outcome, .accept(.replaced))
    }

    func testKnownAndMismatch_UserRejects_RejectsAsMismatch() async {
        let known = KnownHost(host: "h", port: 22, fingerprint: "SHA256:old")
        let outcome = await TOFUDecision.decide(
            host: "h", port: 22, presented: "SHA256:new", known: known,
            userDecision: { _ in .reject }
        )
        XCTAssertEqual(outcome, .reject(.mismatch(host: "h", port: 22, expected: "SHA256:old", presented: "SHA256:new")))
    }

    func testUnknown_UserTrusts_AcceptsAsNewlyTrusted() async {
        let outcome = await TOFUDecision.decide(
            host: "h", port: 22, presented: "SHA256:firstseen", known: nil,
            userDecision: { challenge in
                if case .unknownHost(_, _, let fp) = challenge {
                    XCTAssertEqual(fp, "SHA256:firstseen")
                } else {
                    XCTFail("expected unknownHost challenge")
                }
                return .trust
            }
        )
        XCTAssertEqual(outcome, .accept(.newlyTrusted))
    }

    func testUnknown_UserRejects_RejectsAsRejectedByUser() async {
        let outcome = await TOFUDecision.decide(
            host: "h", port: 22, presented: "SHA256:firstseen", known: nil,
            userDecision: { _ in .reject }
        )
        XCTAssertEqual(outcome, .reject(.rejectedByUser(host: "h", port: 22)))
    }
}
