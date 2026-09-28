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
        let ledger = WaitingLedger().recordingPush(sessionRef: shortRef(s), hostRef: "", at: t0)
        XCTAssertTrue(ledger.isWaiting(s))
        XCTAssertFalse(ledger.isWaiting(other))
    }

    func testMatchesCustomTmuxName() {
        let s = session(tmux: "sshido-payment")
        let ledger = WaitingLedger().recordingPush(sessionRef: "sshido-payment", hostRef: "", at: t0)
        XCTAssertTrue(ledger.isWaiting(s))
    }

    func testOpeningAfterPushClearsWaiting() {
        let s = session()
        let ledger = WaitingLedger()
            .recordingPush(sessionRef: shortRef(s), hostRef: "", at: t0)
            .recordingOpen(s.id, at: t0.addingTimeInterval(1))
        XCTAssertFalse(ledger.isWaiting(s))
    }

    func testPushAfterOpenMarksWaitingAgain() {
        let s = session()
        let ledger = WaitingLedger()
            .recordingOpen(s.id, at: t0)
            .recordingPush(sessionRef: shortRef(s), hostRef: "", at: t0.addingTimeInterval(1))
        XCTAssertTrue(ledger.isWaiting(s))
    }

    func testReplayingOlderDeliveredPushDoesNotReviveWaiting() {
        let s = session()
        let ref = shortRef(s)
        let ledger = WaitingLedger()
            .recordingPush(sessionRef: ref, hostRef: "", at: t0)
            .recordingOpen(s.id, at: t0.addingTimeInterval(5))
            .recordingPush(sessionRef: ref, hostRef: "", at: t0)
        XCTAssertFalse(ledger.isWaiting(s))
        XCTAssertEqual(ledger.pushes[ref], t0)
    }

    func testWaitingHostIDsCoversOnlyHostsWithAWaitingSession() {
        let otherHost = RemoteHost(name: "o", hostname: "o", username: "u")
        let waitingHere = session()
        let quietHere = session()
        let quietThere = Session(hostID: otherHost.id, title: "q")
        let openedThere = Session(hostID: otherHost.id, title: "r")
        let ledger = WaitingLedger()
            .recordingPush(sessionRef: shortRef(waitingHere), hostRef: "", at: t0)
            .recordingPush(sessionRef: shortRef(openedThere), hostRef: "", at: t0)
            .recordingOpen(openedThere.id, at: t0.addingTimeInterval(1))
        XCTAssertEqual(ledger.waitingHostIDs(among: [waitingHere, quietHere, quietThere, openedThere], hosts: [host, otherHost]), [host.id])
        XCTAssertEqual(ledger.waitingHostIDs(among: [quietThere, openedThere], hosts: [host, otherHost]), [])
    }

    func testRoundTripsThroughJSON() throws {
        let s = session()
        let ledger = WaitingLedger()
            .recordingPush(sessionRef: shortRef(s), hostRef: "", at: t0)
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

    private func tailscaleMac(learned: String? = nil) -> RemoteHost {
        RemoteHost(name: "Mac", hostname: "json-mbp.tail1234.ts.net", username: "u", remoteHostname: learned)
    }

    func testHostRefMatchesLearnedHostnameOnly() {
        let learned = tailscaleMac(learned: "Jsons-MacBook-Pro")
        XCTAssertTrue(learned.matches(hostRef: "jsons-macbook-pro"))
        XCTAssertFalse(learned.matches(hostRef: "json-mbp"))
        XCTAssertFalse(learned.matches(hostRef: "Mac"))
    }

    func testHostRefFallsBackToAddressLabelAndName() {
        let mac = tailscaleMac()
        XCTAssertTrue(mac.matches(hostRef: "json-mbp"))
        XCTAssertTrue(mac.matches(hostRef: "MAC"))
        XCTAssertFalse(mac.matches(hostRef: "json"))
        let pi = RemoteHost(name: "Pi", hostname: "192.168.200.103", username: "json")
        XCTAssertFalse(pi.matches(hostRef: "raspberrypi"))
    }

    func testPushWithoutSessionRefMarksHostUntilVisited() {
        let mac = tailscaleMac()
        let ledger = WaitingLedger().recordingPush(sessionRef: "", hostRef: "json-mbp", at: t0)
        XCTAssertEqual(ledger.waitingHostIDs(among: [], hosts: [mac, host]), [mac.id])
        let visited = ledger.recordingHostVisit(mac.id, at: t0.addingTimeInterval(1))
        XCTAssertEqual(visited.waitingHostIDs(among: [], hosts: [mac, host]), [])
    }

    func testPushForUnknownSessionMarksHost() {
        let mac = tailscaleMac()
        let ledger = WaitingLedger().recordingPush(sessionRef: "some-other-tmux", hostRef: "json-mbp", at: t0)
        XCTAssertEqual(ledger.waitingHostIDs(among: [session()], hosts: [mac]), [mac.id])
    }

    func testPushForKnownSessionMarksHostOnlyThroughThatSession() {
        let mac = tailscaleMac()
        let s = Session(hostID: mac.id, title: "s")
        let ledger = WaitingLedger().recordingPush(sessionRef: shortRef(s), hostRef: "json-mbp", at: t0)
        XCTAssertEqual(ledger.waitingHostIDs(among: [s], hosts: [mac]), [mac.id])
        let opened = ledger.recordingOpen(s.id, at: t0.addingTimeInterval(1))
        XCTAssertEqual(opened.waitingHostIDs(among: [s], hosts: [mac]), [])
        XCTAssertEqual(opened.recordingHostVisit(mac.id, at: .distantPast).waitingHostIDs(among: [s], hosts: [mac]), [])
    }

    func testPushAfterVisitMarksHostAgain() {
        let mac = tailscaleMac()
        let ledger = WaitingLedger()
            .recordingHostVisit(mac.id, at: t0)
            .recordingPush(sessionRef: "", hostRef: "json-mbp", at: t0.addingTimeInterval(1))
        XCTAssertEqual(ledger.waitingHostIDs(among: [], hosts: [mac]), [mac.id])
    }

    func testDecodesLedgerSavedBeforeHostRefs() throws {
        let s = session()
        let legacy = #"{"pushes":{"\#(shortRef(s))":0},"opened":[]}"#
        let ledger = try JSONDecoder().decode(WaitingLedger.self, from: Data(legacy.utf8))
        XCTAssertTrue(ledger.isWaiting(s))
        XCTAssertEqual(ledger.hostPushes, [:])
        XCTAssertEqual(ledger.hostVisits, [:])
    }

    @MainActor
    func testStoreRecordsHostRefFromUserInfo() throws {
        let suite = "WaitingLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mac = tailscaleMac()
        WaitingSessionsStore(defaults: defaults).recordPush(userInfo: ["host_ref": "json-mbp"], at: t0)
        XCTAssertEqual(WaitingSessionsStore(defaults: defaults).ledger.waitingHostIDs(among: [], hosts: [mac]), [mac.id])
    }
}
