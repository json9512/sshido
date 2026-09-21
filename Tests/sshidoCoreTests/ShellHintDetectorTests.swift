import XCTest
@testable import sshidoCore

final class ShellHintDetectorTests: XCTestCase {
    private let plain = StyledCell.defaultStyle
    private let code = 95
    private let echo = 98
    private let pink = 96

    private func row(_ parts: (String, Int)...) -> [StyledCell] {
        parts.flatMap { text, style in text.map { StyledCell(character: $0, style: style) } }
    }

    private func commands(_ rows: [[StyledCell]], cols: Int = 52) -> [String] {
        ShellHintDetector.detect(in: rows, cols: cols).map(\.command)
    }

    func testHintInsideOneRow() {
        let rows = [row(("  Or type ", plain), ("! gh auth login", code), (" and tell me when done.", plain))]
        XCTAssertEqual(commands(rows), ["gh auth login"])
    }

    func testSoftWrappedHintKeepsSingleSpaces() {
        let rows = [
            row(("⏺", echo), (" I need you to log in. Please run ", plain), ("! gcloud auth ", code)),
            row(("  ", plain), ("login --no-launch-browser --project ", code)),
            row(("  ", plain), ("my-long-project-name-12345", code), (" in the prompt so the", plain)),
            row(("  output lands here.", plain)),
        ]
        XCTAssertEqual(commands(rows), ["gcloud auth login --no-launch-browser --project my-long-project-name-12345"])
    }

    func testBangAloneAtRowEndJoinsNextRow() {
        let rows = [
            row(("  output lands here.\" then a second line \"Or type ", echo), ("!", code)),
            row(("  ", plain), ("gh auth login", code), (" and tell me when done.\"", echo)),
        ]
        XCTAssertEqual(commands(rows), ["gh auth login"])
    }

    func testHardBrokenTokenJoinsWithoutSpace() {
        let rows = [
            row(("⏺", echo), (" Run ", plain), ("! ls -l ", code)),
            row(("  ", plain), ("/Users/json/a/very/long/path/that/keeps/going/and/", code)),
            row(("  ", plain), ("going/and/going/further/than/one/row/file.txt /tmp", code)),
            row(("  to see the directory listing.", plain)),
        ]
        XCTAssertEqual(rows[1].count, 52)
        XCTAssertEqual(
            commands(rows),
            ["ls -l /Users/json/a/very/long/path/that/keeps/going/and/going/and/going/further/than/one/row/file.txt /tmp"]
        )
    }

    func testUncolouredBangIsIgnored() {
        XCTAssertEqual(commands([row(("  Wow! that worked, run it again", plain))]), [])
        XCTAssertEqual(commands([row(("! not a hint", plain))]), [])
    }

    func testShellModeEchoAndFooterAreIgnored() {
        let rows = [
            row(("! ", pink), (" echo typed-ok", echo)),
            row(("  ⎿  ", plain), ("typed-ok", plain)),
            row(("  ", plain), ("! for shell mode", pink)),
        ]
        XCTAssertEqual(commands(rows), [])
    }

    func testBlankRowEndsAnOpenHint() {
        let rows = [
            row(("  Run ", plain), ("! make test", code)),
            row(),
            row(("  ", plain), ("unrelated code", code)),
        ]
        XCTAssertEqual(commands(rows), ["make test"])
    }

    func testConsecutiveHintsStaySeparate() {
        let rows = [
            row(("  ", plain), ("! first one", code)),
            row(("  ", plain), ("! second one", code)),
        ]
        XCTAssertEqual(commands(rows), ["first one", "second one"])
    }

    func testRepeatedHintIsReportedOnce() {
        let rows = [
            row(("  ", plain), ("! gh auth login", code), (" first", plain)),
            row(("  ", plain), ("! gh auth login", code), (" again", plain)),
        ]
        XCTAssertEqual(commands(rows), ["gh auth login"])
    }

    func testHintInsideNarrowTmuxWindow() {
        let filler = ("│····", plain)
        let rows = [
            row(("  Please run ", plain), ("! gcloud auth login --launch ", code), ("     ", plain), filler),
            row(("  ", plain), ("--project demo", code), (" now.", plain), ("                          ", plain), filler),
            row(("  third row of plain text here", plain), ("                 ", plain), filler),
        ]
        XCTAssertEqual(commands(rows), ["gcloud auth login --launch --project demo"])
    }

    func testPromptInputCarriesTheBangPrefix() {
        XCTAssertEqual(DetectedShellHint(command: "gh auth login").promptInput, "! gh auth login")
    }
}
