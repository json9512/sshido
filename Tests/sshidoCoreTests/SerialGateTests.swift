import XCTest
@testable import sshidoCore

private actor Counter {
    private(set) var running = 0
    private(set) var peak = 0
    private(set) var finished = 0

    func enter() {
        running += 1
        peak = max(peak, running)
    }

    func leave() {
        running -= 1
        finished += 1
    }
}

final class SerialGateTests: XCTestCase {
    func testRunsOneOperationAtATime() async {
        let gate = SerialGate()
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await gate.run {
                        await counter.enter()
                        try? await Task.sleep(for: .milliseconds(5))
                        await counter.leave()
                    }
                }
            }
        }
        let peak = await counter.peak
        let finished = await counter.finished
        XCTAssertEqual(peak, 1)
        XCTAssertEqual(finished, 12)
    }

    func testReleasesAfterAThrow() async {
        struct Boom: Error {}
        let gate = SerialGate()
        do {
            try await gate.run { throw Boom() }
            XCTFail("the error must pass through")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        let value = await gate.run { 42 }
        XCTAssertEqual(value, 42)
    }
}
