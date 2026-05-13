import XCTest
@testable import sshidoCore
@testable import sshidoModels

final class KnownHostStoreTests: XCTestCase {
    private func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshido-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("known-hosts.json")
    }

    func testAddAndGetRoundTrip() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "prod.example.com", port: 22, fingerprint: "SHA256:abc")
        let got = await store.get(host: "prod.example.com", port: 22)
        XCTAssertEqual(got?.fingerprint, "SHA256:abc")
    }

    func testGetMissingReturnsNil() async {
        let store = KnownHostStore(fileURL: tempStoreURL())
        let got = await store.get(host: "never-seen", port: 22)
        XCTAssertNil(got)
    }

    func testAddIsIdempotentWithSameKey() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "h", port: 22, fingerprint: "SHA256:first")
        try await store.add(host: "h", port: 22, fingerprint: "SHA256:should-not-overwrite")
        let got = await store.get(host: "h", port: 22)
        XCTAssertEqual(got?.fingerprint, "SHA256:first", "add() must not overwrite — use replace() for that")
    }

    func testReplaceOverwrites() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "h", port: 22, fingerprint: "SHA256:old")
        try await store.replace(host: "h", port: 22, fingerprint: "SHA256:new")
        let got = await store.get(host: "h", port: 22)
        XCTAssertEqual(got?.fingerprint, "SHA256:new")
    }

    func testRemove() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "h", port: 22, fingerprint: "SHA256:x")
        try await store.remove(host: "h", port: 22)
        let got = await store.get(host: "h", port: 22)
        XCTAssertNil(got)
    }

    func testPersistAcrossInstances() async throws {
        let url = tempStoreURL()
        do {
            let first = KnownHostStore(fileURL: url)
            try await first.add(host: "persist.example", port: 2222, fingerprint: "SHA256:keep")
        }
        let second = KnownHostStore(fileURL: url)
        let got = await second.get(host: "persist.example", port: 2222)
        XCTAssertEqual(got?.fingerprint, "SHA256:keep")
    }

    func testAllReturnsSortedByHost() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "zeta.example", port: 22, fingerprint: "SHA256:z")
        try await store.add(host: "alpha.example", port: 22, fingerprint: "SHA256:a")
        try await store.add(host: "mu.example", port: 22, fingerprint: "SHA256:m")
        let all = await store.all()
        XCTAssertEqual(all.map(\.host), ["alpha.example", "mu.example", "zeta.example"])
    }

    func testPortIsPartOfKey() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        try await store.add(host: "h", port: 22,   fingerprint: "SHA256:p22")
        try await store.add(host: "h", port: 2222, fingerprint: "SHA256:p2222")
        let a = await store.get(host: "h", port: 22)
        let b = await store.get(host: "h", port: 2222)
        XCTAssertEqual(a?.fingerprint, "SHA256:p22")
        XCTAssertEqual(b?.fingerprint, "SHA256:p2222")
    }

    func testTouchLastSeenAdvancesTimestamp() async throws {
        let store = KnownHostStore(fileURL: tempStoreURL())
        let initial = Date(timeIntervalSince1970: 1_000_000)
        try await store.add(host: "h", port: 22, fingerprint: "SHA256:x", at: initial)
        let later = Date(timeIntervalSince1970: 2_000_000)
        await store.touchLastSeen(host: "h", port: 22, at: later)
        let got = await store.get(host: "h", port: 22)
        XCTAssertEqual(got?.firstSeen, initial)
        XCTAssertEqual(got?.lastSeen, later)
    }
}
