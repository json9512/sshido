import XCTest
@testable import sshidoCore
import sshidoModels

final class TmuxSessionListTests: XCTestCase {
    func testParseTypicalOutput() {
        let output = """
        1753921200:2:1:sshido-3F2A1B9C
        1753924800:1:0:work
        """
        let sessions = TmuxSessionList.parse(output)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].name, "sshido-3F2A1B9C")
        XCTAssertEqual(sessions[0].windows, 2)
        XCTAssertTrue(sessions[0].attached)
        XCTAssertEqual(sessions[0].createdAt, Date(timeIntervalSince1970: 1_753_921_200))
        XCTAssertEqual(sessions[1].name, "work")
        XCTAssertEqual(sessions[1].windows, 1)
        XCTAssertFalse(sessions[1].attached)
    }

    func testParseEmptyOutput() {
        XCTAssertTrue(TmuxSessionList.parse("").isEmpty)
        XCTAssertTrue(TmuxSessionList.parse("\n\n").isEmpty)
    }

    func testParseSkipsMalformedLines() {
        let output = """
        no server running on /private/tmp/tmux-501/default
        1753921200:2:1:ok
        garbage:x:y:z
        1753921200:2
        """
        let sessions = TmuxSessionList.parse(output)
        XCTAssertEqual(sessions.map(\.name), ["ok"])
    }

    func testParseMultipleAttachedClients() {
        let sessions = TmuxSessionList.parse("1753921200:3:2:pair")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].attached)
    }

    func testListCommandAlwaysExitsZeroShape() {
        let cmd = TmuxSessionList.listCommand(tmuxPath: "/usr/bin/tmux")
        XCTAssertTrue(cmd.hasSuffix("; true"))
        XCTAssertTrue(cmd.contains("#{session_created}:#{session_windows}:#{session_attached}:#{session_name}"))
        XCTAssertTrue(cmd.hasPrefix("'/usr/bin/tmux' ls -F"))
    }

    func testListCommandQuotesPathWithSpaces() {
        let cmd = TmuxSessionList.listCommand(tmuxPath: "/opt/my tools/tmux")
        XCTAssertTrue(cmd.hasPrefix("'/opt/my tools/tmux' ls"))
    }

    func testListCommandEscapesSingleQuote() {
        let cmd = TmuxSessionList.listCommand(tmuxPath: "/opt/it's/tmux")
        XCTAssertTrue(cmd.hasPrefix("'/opt/it'\\''s/tmux' ls"))
    }

    func testKillCommandUsesExactTargetMatch() {
        let cmd = TmuxSessionList.killCommand(tmuxPath: "/usr/bin/tmux", sessionName: "sshido-1863CC30")
        XCTAssertTrue(cmd.contains("kill-session -t '=sshido-1863CC30'"),
                      "missing '=' prefix would let tmux prefix-match and kill a different session; got: \(cmd)")
        XCTAssertTrue(cmd.hasSuffix("; true"))
        XCTAssertTrue(cmd.hasPrefix("'/usr/bin/tmux' "))
    }

    func testKillCommandEscapesSessionName() {
        let cmd = TmuxSessionList.killCommand(tmuxPath: "/usr/bin/tmux", sessionName: "it's; rm -rf /")
        XCTAssertTrue(cmd.contains("'=it'\\''s; rm -rf /'"), "session name not safely quoted; got: \(cmd)")
    }

    func testResolveCommandTriesLoginShellThenCandidates() {
        let cmd = TmuxSessionList.resolveCommand
        XCTAssertTrue(cmd.hasPrefix("${SHELL:-/bin/sh} -lc 'command -v tmux'"))
        XCTAssertTrue(cmd.contains("/opt/homebrew/bin/tmux"))
        XCTAssertTrue(cmd.contains("/usr/bin/tmux"))
        XCTAssertTrue(cmd.hasSuffix("; true"))
    }

    func testParseResolvedPath() {
        XCTAssertEqual(TmuxSessionList.parseResolvedPath("/opt/homebrew/bin/tmux\n"), "/opt/homebrew/bin/tmux")
        XCTAssertEqual(TmuxSessionList.parseResolvedPath("/usr/bin/tmux"), "/usr/bin/tmux")
    }

    func testParseResolvedPathRejectsNonPaths() {
        XCTAssertNil(TmuxSessionList.parseResolvedPath(""))
        XCTAssertNil(TmuxSessionList.parseResolvedPath("\n\n"))
        XCTAssertNil(TmuxSessionList.parseResolvedPath("tmux not found"))
        XCTAssertNil(TmuxSessionList.parseResolvedPath("Unknown option: `-lc'"))
    }

    func testParseResolvedPathSkipsLeadingNoise() {
        let output = "Welcome to the host!\n/opt/homebrew/bin/tmux\n"
        XCTAssertEqual(TmuxSessionList.parseResolvedPath(output), "/opt/homebrew/bin/tmux")
    }

    func testSessionDecodesLegacyJSONWithoutTmuxName() throws {
        let legacy = """
        {"id":"3F2A1B9C-0000-0000-0000-000000000000","hostID":"00000000-0000-0000-0000-000000000001","title":"Session 1","createdAt":0}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(legacy.utf8))
        XCTAssertNil(session.tmuxName)
        XCTAssertEqual(session.title, "Session 1")
    }

    func testSessionRoundTripsTmuxName() throws {
        let original = Session(hostID: UUID(), title: "work", tmuxName: "work")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded.tmuxName, "work")
    }
}
