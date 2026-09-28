import XCTest
@testable import sshidoModels
@testable import sshidoCore

final class WaitingLedgerTests: XCTestCase {
    private let host = RemoteHost(name: "t", hostname: "h", username: "u")
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func session(tmux: String? = nil) -> Session {
        Session(hostID: host.id, title: "s", tmuxName: tmux)
    }

    private func shortRef(_ s: Session) -> String {
        "sshido-" + String(s.id.uuidString.prefix(8))
    }

    func testPushMarksMatchingSessionWaiting() {
        let s = session()
        let other = session()
        let ledger = WaitingLedger().recordingPush(ref: shortRef(s), at: t0)
        XCTAssertTrue(ledger.isWaiting(s))
        XCTAssertFalse(ledger.isWaiting(other))
    }

    func testMatchesCustomTmuxName() {
        let s = session(tmux: "sshido-payment")
        let ledger = WaitingLedger().recordingPush(ref: "sshido-payment", at: t0)
        XCTAssertTrue(ledger.isWaiting(s))
    }

    func testOpeningAfterPushClearsWaiting() {
        let s = session()
        let ledger = WaitingLedger()
            .recordingPush(ref: shortRef(s), at: t0)
            .recordingOpen(s.id, at: t0.addingTimeInterval(1))
        XCTAssertFalse(ledger.isWaiting(s))
    }

    func testPushAfterOpenMarksWaitingAgain() {
        let s = session()
        let ledger = WaitingLedger()
            .recordingOpen(s.id, at: t0)
            .recordingPush(ref: shortRef(s), at: t0.addingTimeInterval(1))
        XCTAssertTrue(ledger.isWaiting(s))
    }

    func testReplayingOlderDeliveredPushDoesNotReviveWaiting() {
        let s = session()
        let ref = shortRef(s)
        let ledger = WaitingLedger()
            .recordingPush(ref: ref, at: t0)
            .recordingOpen(s.id, at: t0.addingTimeInterval(5))
            .recordingPush(ref: ref, at: t0)
        XCTAssertFalse(ledger.isWaiting(s))
        XCTAssertEqual(ledger.pushes[ref], t0)
    }

    func testRoundTripsThroughJSON() throws {
        let s = session()
        let ledger = WaitingLedger()
            .recordingPush(ref: shortRef(s), at: t0)
            .recordingOpen(s.id, at: t0.addingTimeInterval(-1))
        let decoded = try JSONDecoder().decode(WaitingLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
    }

    @MainActor
    func testStorePersistsAcrossInstances() throws {
        let suite = "WaitingLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = session()
        WaitingSessionsStore(defaults: defaults).recordPush(userInfo: ["session_ref": shortRef(s)], at: t0)
        XCTAssertTrue(WaitingSessionsStore(defaults: defaults).isWaiting(s))
        WaitingSessionsStore(defaults: defaults).markOpened(s.id, at: t0.addingTimeInterval(1))
        XCTAssertFalse(WaitingSessionsStore(defaults: defaults).isWaiting(s))
    }

    @MainActor
    func testStoreIgnoresPushWithoutSessionRef() throws {
        let suite = "WaitingLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WaitingSessionsStore(defaults: defaults)
        store.recordPush(userInfo: ["session_ref": ""], at: t0)
        store.recordPush(userInfo: [:], at: t0)
        XCTAssertEqual(store.ledger, WaitingLedger())
    }
}
