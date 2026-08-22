import XCTest
@testable import sshidoCore

final class ShellBootstrapGateTests: XCTestCase {
    private func makeChannel() -> CitadelSSHChannel {
        CitadelSSHChannel(
            host: "example.invalid",
            port: 22,
            user: "u",
            auth: .password("p"),
            bootstrap: ShellBootstrap(prepare: nil, typed: { _ in "exec tmux attach" })
        )
    }

    func testKeystrokesBeforeTheBootstrapAreHeldInOrder() {
        let channel = makeChannel()
        channel.enqueueInput(Array("c".utf8))
        channel.enqueueInput(Array("d".utf8))
        XCTAssertEqual(channel.heldInput, [Array("c".utf8), Array("d".utf8)])
    }

    func testOpeningTheGateReleasesEverythingHeld() {
        let channel = makeChannel()
        channel.enqueueInput(Array("c".utf8))
        channel.openInputGate()
        XCTAssertTrue(channel.heldInput.isEmpty)
    }

    func testInputAfterTheGateOpensIsNotHeld() {
        let channel = makeChannel()
        channel.openInputGate()
        channel.enqueueInput(Array("ls\r".utf8))
        XCTAssertTrue(channel.heldInput.isEmpty)
    }
}
