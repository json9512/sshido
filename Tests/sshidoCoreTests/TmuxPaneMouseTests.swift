import XCTest
@testable import sshidoCore

final class TmuxPaneMouseTests: XCTestCase {
    func testStateCommandTargetsAndExitsZero() {
        let cmd = TmuxPaneMouse.stateCommand(tmuxPath: "/usr/bin/tmux", target: "$3")
        XCTAssertTrue(cmd.contains("display-message -p -t '$3'"))
        XCTAssertFalse(cmd.contains("-t $3"), "unquoted $3 expands to a positional param; got: \(cmd)")
        XCTAssertTrue(cmd.contains("'#{mouse_any_flag}:#{pane_current_command}'"))
        XCTAssertTrue(cmd.hasSuffix("; true"))
    }

    func testParsesBothFlagStates() {
        XCTAssertEqual(TmuxPaneMouse.parse("1:bash\n"), PaneMouseState(appWantsMouse: true, command: "bash"))
        XCTAssertEqual(TmuxPaneMouse.parse("0:bash\n"), PaneMouseState(appWantsMouse: false, command: "bash"))
    }

    func testParseSkipsBannerNoise() {
        XCTAssertEqual(
            TmuxPaneMouse.parse("Welcome to pi!\n1:node\n"),
            PaneMouseState(appWantsMouse: true, command: "node")
        )
    }

    // A missing session prints a bare ":" — no state, so the caller must fail open.
    func testParseRejectsEmptyAndMalformed() {
        XCTAssertNil(TmuxPaneMouse.parse(":"))
        XCTAssertNil(TmuxPaneMouse.parse(""))
        XCTAssertNil(TmuxPaneMouse.parse("can't find session\n"))
        XCTAssertNil(TmuxPaneMouse.parse("2:bash"))
        XCTAssertNil(TmuxPaneMouse.parse("1:\n"))
    }

    func testForwardsWhenTmuxItselfHandlesTheWheel() {
        XCTAssertTrue(TmuxPaneMouse.forwardsWheel(PaneMouseState(appWantsMouse: false, command: "bash")),
                      "flag off means tmux scrolls the pane itself; forwarding must not change")
    }

    func testForwardsToALiveTUIThatAskedForMouse() {
        for app in ["node", "vim", "nvim", "htop", "claude"] {
            XCTAssertTrue(
                TmuxPaneMouse.forwardsWheel(PaneMouseState(appWantsMouse: true, command: app)),
                "\(app) asked for mouse events and must keep receiving them"
            )
        }
    }

    // The bug: a TUI exited without clearing the flag, so the shell that inherited the
    // pane echoes the wheel bytes as text.
    func testWithholdsFromAShellLeftHoldingTheFlag() {
        for shell in ["bash", "zsh", "sh", "fish", "dash", "-zsh", "/bin/bash", "ZSH"] {
            XCTAssertFalse(
                TmuxPaneMouse.forwardsWheel(PaneMouseState(appWantsMouse: true, command: shell)),
                "\(shell) would echo the wheel bytes as text"
            )
        }
    }

    func testShellDetectionDoesNotCatchLookalikes() {
        for app in ["shell-gpt", "bashtop", "zsh-helper", "fisher", "ssh"] {
            XCTAssertFalse(TmuxPaneMouse.isShell(app), "\(app) is not a shell")
        }
    }
}
