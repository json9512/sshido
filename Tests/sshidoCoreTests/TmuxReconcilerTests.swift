import XCTest
@testable import sshidoCore
import sshidoModels

final class TmuxReconcilerTests: XCTestCase {
    private let hostID = UUID()

    private func remote(
        _ id: String, _ name: String, created: TimeInterval = 1_753_921_200
    ) -> RemoteTmuxSession {
        RemoteTmuxSession(
            sessionID: id, name: name, windows: 1,
            createdAt: Date(timeIntervalSince1970: created), attached: false
        )
    }

    private func local(
        name: String?, sessionID: String? = nil, created: TimeInterval? = nil
    ) -> Session {
        Session(
            hostID: hostID, title: name ?? "Session 1", tmuxName: name,
            tmuxSessionID: sessionID,
            tmuxCreatedAt: created.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func plan(
        _ locals: [Session], _ remotes: [RemoteTmuxSession], derived: String = "derived"
    ) -> (bindings: [TmuxBinding], unknown: [RemoteTmuxSession]) {
        TmuxReconciler.plan(locals: locals, remotes: remotes, derivedName: { _ in derived })
    }

    func testNameMatchLearnsSessionID() {
        let s = local(name: "work")
        let result = plan([s], [remote("$3", "work")])
        XCTAssertEqual(result.bindings, [TmuxBinding(localID: s.id, remote: remote("$3", "work"))])
        XCTAssertTrue(result.unknown.isEmpty)
    }

    func testLegacySessionMatchesOnDerivedName() {
        let s = local(name: nil)
        let result = plan([s], [remote("$1", "derived")], derived: "derived")
        XCTAssertEqual(result.bindings.map(\.localID), [s.id])
        XCTAssertEqual(result.bindings.first?.remote.sessionID, "$1")
    }

    func testFollowsRenameMadeOnTheServer() {
        let s = local(name: "work", sessionID: "$3", created: 1_753_921_200)
        let renamed = remote("$3", "deploy box", created: 1_753_921_200)
        let result = plan([s], [renamed])
        XCTAssertEqual(result.bindings, [TmuxBinding(localID: s.id, remote: renamed)])
        XCTAssertTrue(result.unknown.isEmpty, "renamed session must not also show as unknown")
    }

    // tmux hands out "$0" again after a server restart; the creation stamp is the guard.
    func testDoesNotBindRecycledSessionIDFromRestartedServer() {
        let s = local(name: "work", sessionID: "$0", created: 1_753_921_200)
        let stranger = remote("$0", "someone-else", created: 1_753_999_999)
        let result = plan([s], [stranger])
        XCTAssertTrue(result.bindings.isEmpty, "id reuse must not silently rebind our session")
        XCTAssertEqual(result.unknown, [stranger])
    }

    func testIDMatchIsSkippedWithoutARecordedCreationStamp() {
        let s = local(name: "work", sessionID: "$3", created: nil)
        let result = plan([s], [remote("$3", "renamed")])
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertEqual(result.unknown.map(\.name), ["renamed"])
    }

    func testUntrackedSessionsAreReturnedForAdoption() {
        let s = local(name: "work")
        let result = plan([s], [remote("$3", "work"), remote("$4", "scratch")])
        XCTAssertEqual(result.unknown.map(\.name), ["scratch"])
    }

    func testTwoLocalsCannotClaimTheSameRemote() {
        let a = local(name: "work")
        let b = local(name: "work")
        let result = plan([a, b], [remote("$3", "work")])
        XCTAssertEqual(result.bindings.count, 1)
        XCTAssertEqual(result.bindings.first?.localID, a.id)
    }

    func testNameMatchWinsOverAStaleIDMatch() {
        let s = local(name: "work", sessionID: "$9", created: 1_753_921_200)
        let byName = remote("$3", "work")
        let byStaleID = remote("$9", "unrelated", created: 1_753_921_200)
        let result = plan([s], [byStaleID, byName])
        XCTAssertEqual(result.bindings.map(\.remote), [byName])
        XCTAssertEqual(result.unknown, [byStaleID])
    }

    func testKilledSessionIsNotRebound() {
        let s = local(name: "work", sessionID: "$3", created: 1_753_921_200)
        let result = plan([s], [remote("$4", "someone-else")])
        XCTAssertTrue(result.bindings.isEmpty, "our session is gone; nothing may claim it")
        XCTAssertEqual(result.unknown.map(\.name), ["someone-else"])
    }

    func testNoRemotesLeavesEverythingUnbound() {
        let s = local(name: "work", sessionID: "$3", created: 1_753_921_200)
        let result = plan([s], [])
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertTrue(result.unknown.isEmpty)
    }
}
