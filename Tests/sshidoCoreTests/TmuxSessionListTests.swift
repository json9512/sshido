import XCTest
@testable import sshidoCore
import sshidoModels

final class TmuxSessionListTests: XCTestCase {
    func testParseTypicalOutput() {
        let output = """
        $0:1753921200:2:1:sshido-3F2A1B9C
        $1:1753924800:1:0:work
        """
        let sessions = TmuxSessionList.parse(output)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].sessionID, "$0")
        XCTAssertEqual(sessions[1].sessionID, "$1")
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
        $2:1753921200:2:1:ok
        $3:garbage:x:y:z
        1753921200:2:1:missing-id
        $4:1753921200:2
        """
        let sessions = TmuxSessionList.parse(output)
        XCTAssertEqual(sessions.map(\.name), ["ok"])
    }

    func testParseMultipleAttachedClients() {
        let sessions = TmuxSessionList.parse("$7:1753921200:3:2:pair")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].attached)
    }

    func testListCommandAlwaysExitsZeroShape() {
        let cmd = TmuxSessionList.listCommand(tmuxPath: "/usr/bin/tmux")
        XCTAssertTrue(cmd.hasSuffix("; true"))
        XCTAssertTrue(cmd.contains("#{session_id}:#{session_created}:#{session_windows}:#{session_attached}:#{session_name}"))
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

    func testKillCommandQuotesSessionIDTarget() {
        let cmd = TmuxSessionList.killCommand(tmuxPath: "/usr/bin/tmux", target: "$3")
        XCTAssertTrue(cmd.contains("kill-session -t '$3'"))
        XCTAssertFalse(cmd.contains("-t $3"), "unquoted $3 expands to a positional param; got: \(cmd)")
        XCTAssertTrue(cmd.hasSuffix("; true"))
        XCTAssertTrue(cmd.hasPrefix("'/usr/bin/tmux' "))
    }

    func testKillCommandEscapesTarget() {
        let cmd = TmuxSessionList.killCommand(tmuxPath: "/usr/bin/tmux", target: "=it's; rm -rf /")
        XCTAssertTrue(cmd.contains("'=it'\\''s; rm -rf /'"), "target not safely quoted; got: \(cmd)")
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

    func testSessionNameUsesHostPrefixAndShortID() {
        let id = UUID(uuidString: "3F2A1B9C-1111-2222-3333-444444444444")!
        XCTAssertEqual(TmuxSessionList.sessionName(prefix: "work", sessionID: id), "work-3F2A1B9C")
    }

    func testSessionNameFallsBackToSshidoPrefix() {
        let id = UUID(uuidString: "3F2A1B9C-1111-2222-3333-444444444444")!
        XCTAssertEqual(TmuxSessionList.sessionName(prefix: "", sessionID: id), "sshido-3F2A1B9C")
    }

    func testBootstrapAttachesByIDBeforeCreating() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "/usr/bin/tmux", sessionName: "work", sessionID: "$3"
        )
        XCTAssertTrue(cmd.contains("has-session -t '$3'"))
        XCTAssertTrue(cmd.contains("exec '/usr/bin/tmux' attach -t '$3'"))
        XCTAssertTrue(cmd.contains("new-session -d -s 'work'"),
                      "must still create when the id is gone; got: \(cmd)")
        guard let attach = cmd.range(of: "attach -t '$3'"), let new = cmd.range(of: "new-session") else {
            return XCTFail("missing branches: \(cmd)")
        }
        XCTAssertTrue(attach.lowerBound < new.lowerBound, "attach by id must be tried first")
    }

    // A TUI that dies without clearing mouse reporting leaves the pane echoing wheel
    // bytes as text; tmux owning the mouse keeps those bytes away from the shell.
    func testBootstrapEnablesMouseBeforeAttaching() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "tmux", sessionName: "work", sessionID: nil
        )
        XCTAssertTrue(cmd.contains("set -t 'work' mouse on"))
        guard let set = cmd.range(of: "mouse on"), let attach = cmd.range(of: "exec 'tmux' attach") else {
            return XCTFail("missing steps: \(cmd)")
        }
        XCTAssertTrue(set.lowerBound < attach.lowerBound, "mouse must be set before attaching")
    }

    func testBootstrapScopesMouseToTheSessionNotGlobally() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "tmux", sessionName: "work", sessionID: nil
        )
        XCTAssertFalse(cmd.contains("set -g mouse"), "must not touch the user's global tmux config")
    }

    func testBootstrapAttachesExactNameSoPrefixesAreNotHijacked() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "tmux", sessionName: "work", sessionID: nil
        )
        XCTAssertTrue(cmd.contains("attach -t '=work'"))
        XCTAssertTrue(cmd.contains("has-session -t '=work'"))
    }

    func testBootstrapQuotesSessionIDSoShellCannotExpandIt() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "/usr/bin/tmux", sessionName: "work", sessionID: "$3"
        )
        XCTAssertFalse(cmd.contains("-t $3"), "unquoted $3 expands to a positional param; got: \(cmd)")
    }

    func testBootstrapWithoutKnownIDOnlyCreates() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "tmux", sessionName: "sshido-3F2A1B9C", sessionID: nil
        )
        XCTAssertFalse(cmd.contains("attach -t '$"))
        XCTAssertTrue(cmd.contains("new-session -d -s 'sshido-3F2A1B9C' -e SSHIDO_SESSION=1"))
        XCTAssertTrue(cmd.contains("exec 'tmux' attach -t '=sshido-3F2A1B9C'"))
    }

    func testBootstrapKeepsTmuxGuardAndEnvSetup() {
        let cmd = TmuxSessionList.bootstrapCommand(
            tmuxPath: "tmux", sessionName: "work", sessionID: nil
        )
        XCTAssertTrue(cmd.hasPrefix("if command -v 'tmux' >/dev/null 2>&1; then "))
        XCTAssertTrue(cmd.contains("unset TMUX TMUX_PANE"))
        XCTAssertTrue(cmd.contains("setenv -g SSHIDO_SESSION 1"))
        XCTAssertTrue(cmd.hasSuffix("; fi"))
    }

    func testRenameCommandTargetsAndReadsBackName() {
        let cmd = TmuxSessionList.renameCommand(
            tmuxPath: "/usr/bin/tmux", target: "$3", newName: "deploy box"
        )
        XCTAssertTrue(cmd.contains("rename-session -t '$3' 'deploy box'"))
        XCTAssertTrue(cmd.contains("display-message -p -t '$3' '#{session_name}'"),
                      "must read back the name tmux settled on; got: \(cmd)")
        XCTAssertTrue(cmd.hasSuffix("; true"))
    }

    func testRenameCommandEscapesInjection() {
        let cmd = TmuxSessionList.renameCommand(
            tmuxPath: "/usr/bin/tmux", target: "=old", newName: "a'; rm -rf /; echo '"
        )
        XCTAssertTrue(cmd.contains("'a'\\''; rm -rf /; echo '\\'''"), "unsafe quoting: \(cmd)")
    }

    // tmux rewrites "." and ":" to "_" and still reports success.
    func testParseRenameResultReturnsServerName() {
        let out = "SSHIDO_RENAMED:a_b\n"
        XCTAssertEqual(TmuxSessionList.parseRenameResult(out), .renamed("a_b"))
    }

    func testParseRenameResultKeepsSpacesInName() {
        XCTAssertEqual(
            TmuxSessionList.parseRenameResult("SSHIDO_RENAMED:deploy box\n"),
            .renamed("deploy box")
        )
    }

    func testParseRenameResultSurvivesBannerNoise() {
        let out = "Welcome to pi!\nSSHIDO_RENAMED:work\n"
        XCTAssertEqual(TmuxSessionList.parseRenameResult(out), .renamed("work"))
    }

    func testParseRenameResultReportsDuplicate() {
        XCTAssertEqual(
            TmuxSessionList.parseRenameResult("duplicate session: other\n"),
            .failed("duplicate session: other")
        )
    }

    func testParseRenameResultReportsEmptyOutput() {
        guard case .failed = TmuxSessionList.parseRenameResult("") else {
            return XCTFail("empty output must not read as success")
        }
    }

    func testDisplayNamePrefersTmuxName() {
        let host = RemoteHost(name: "pi", hostname: "h", username: "u")
        let s = Session(hostID: host.id, title: "json@pi: ~", tmuxName: "deploy box")
        XCTAssertEqual(s.displayName(on: host), "deploy box")
    }

    func testDisplayNameDerivesNameForLegacySessions() {
        let host = RemoteHost(name: "pi", hostname: "h", username: "u", tmuxSession: "sshido")
        let id = UUID(uuidString: "3F2A1B9C-1111-2222-3333-444444444444")!
        let s = Session(id: id, hostID: host.id, title: "json@pi: ~")
        XCTAssertEqual(s.displayName(on: host), "sshido-3F2A1B9C")
    }

    func testDisplayNameFallsBackToTitleWithoutTmux() {
        let host = RemoteHost(name: "pi", hostname: "h", username: "u", useTmux: false)
        let s = Session(hostID: host.id, title: "Session 1")
        XCTAssertEqual(s.displayName(on: host), "Session 1")
    }

    func testSessionRoundTripsTmuxBinding() throws {
        let original = Session(
            hostID: UUID(), title: "work", tmuxName: "work",
            tmuxSessionID: "$3", tmuxCreatedAt: Date(timeIntervalSince1970: 1_753_921_200)
        )
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.tmuxSessionID, "$3")
        XCTAssertEqual(decoded.tmuxCreatedAt, Date(timeIntervalSince1970: 1_753_921_200))
    }

    func testSessionDecodesJSONWrittenBeforeTmuxBinding() throws {
        let old = """
        {"id":"3F2A1B9C-0000-0000-0000-000000000000","hostID":"00000000-0000-0000-0000-000000000001","title":"work","createdAt":0,"tmuxName":"work"}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(old.utf8))
        XCTAssertEqual(session.tmuxName, "work")
        XCTAssertNil(session.tmuxSessionID)
        XCTAssertNil(session.tmuxCreatedAt)
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
