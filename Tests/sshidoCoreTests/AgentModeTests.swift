import XCTest
@testable import sshidoCore
import sshidoModels

final class AgentModeTests: XCTestCase {
    let orchestratorLine = #"{"type":"agent","agent":{"id":"2fab0383","chatId":"c1","name":"orchestrator","role":"orchestrator","harness":"local","model":"qwen3.6:35b-instruct","status":"idle","container":"sshido-agent-2fab0383","createdAt":1790651931922,"updatedAt":1790651950826}}"#
    let userLine = #"{"type":"message","message":{"id":1,"chatId":"c1","author":"you","kind":"user","text":"Create the file","createdAt":1790651931746}}"#
    let doneLine = #"{"type":"message","message":{"id":4,"chatId":"c1","agentId":"0d751e6d","author":"hello-creator","kind":"done","text":"Done.","createdAt":1790651945748}}"#
    let needsInputLine = #"{"type":"message","message":{"id":5,"chatId":"c1","agentId":"0d751e6d","author":"w","kind":"needs_input","text":"Which db?","createdAt":1}}"#

    private func feed(_ chunks: [String]) -> [AgentLineDecoder.Output] {
        let (_, outputs) = chunks.reduce((AgentLineDecoder(), [AgentLineDecoder.Output]())) { acc, chunk in
            let (next, out) = acc.0.feeding(Data(chunk.utf8))
            return (next, acc.1 + out)
        }
        return outputs
    }

    func testDecodesRealDaemonLines() {
        let outputs = feed([orchestratorLine + "\n" + userLine + "\n" + doneLine + "\n" + #"{"type":"ready"}"# + "\n"])
        XCTAssertEqual(outputs.count, 4)
        guard case .event(.agent(let agent)) = outputs[0] else { return XCTFail("want agent, got \(outputs[0])") }
        XCTAssertTrue(agent.isOrchestrator)
        XCTAssertEqual(agent.status, .idle)
        XCTAssertNil(agent.task)
        guard case .event(.message(let user)) = outputs[1] else { return XCTFail("want message") }
        XCTAssertEqual(user.kind, .user)
        XCTAssertNil(user.agentId)
        guard case .event(.message(let done)) = outputs[2] else { return XCTFail("want message") }
        XCTAssertEqual(done.kind, .done)
        XCTAssertEqual(done.agentId, "0d751e6d")
        XCTAssertEqual(outputs[3], .event(.ready))
    }

    func testDecodesAttachmentMessage() {
        let line = #"{"type":"message","message":{"id":9,"chatId":"c1","agentId":"a1","author":"orchestrator","kind":"file","text":"front page","createdAt":1,"attachment":{"name":"hn.png","mime":"image/png","size":138405}}}"#
        guard case .event(.message(let m)) = feed([line + "\n"]).first else { return XCTFail("want message") }
        XCTAssertEqual(m.kind, .file)
        XCTAssertEqual(m.attachment, AgentAttachment(name: "hn.png", mime: "image/png", size: 138405))
        XCTAssertTrue(m.attachment?.isImage == true)
        XCTAssertFalse(m.attachment?.isVideo == true)
    }

    func testFileCommandAndWorkspaceMount() {
        XCTAssertEqual(AgentHostCommands.file(podman: "/opt/homebrew/bin/podman", messageID: 42),
                       "'/opt/homebrew/bin/podman' exec sshido-agents /usr/local/bin/sshido-agents file 42")
        let cmd = AgentHostCommands.startDaemon(podman: "podman", socketPath: "/s", settings: .default, hostName: "h", notify: false)
        XCTAssertTrue(cmd.contains("-v sshido-agents-workspace:/workspace "))
        XCTAssertFalse(cmd.contains(":/workspace:ro"))
    }

    func testNeedsInputKind() {
        guard case .event(.message(let m)) = feed([needsInputLine + "\n"]).first else { return XCTFail("want message") }
        XCTAssertEqual(m.kind, .needsInput)
    }

    func testSplitsLinesAcrossChunks() {
        let whole = doneLine + "\n"
        let mid = whole.index(whole.startIndex, offsetBy: 30)
        let outputs = feed([String(whole[..<mid]), String(whole[mid...])])
        XCTAssertEqual(outputs.count, 1)
        guard case .event(.message(let m)) = outputs[0] else { return XCTFail("want message") }
        XCTAssertEqual(m.id, 4)
    }

    func testHoldsPartialLineUntilNewline() {
        let (_, outputs) = AgentLineDecoder().feeding(Data(doneLine.utf8))
        XCTAssertTrue(outputs.isEmpty)
    }

    func testReportsUndecodableLines() {
        let outputs = feed(["not json\n", #"{"type":"mystery"}"# + "\n"])
        XCTAssertEqual(outputs, [.undecodable("not json"), .undecodable(#"{"type":"mystery"}"#)])
    }

    func testEncodesRequestsAsLines() throws {
        let line = try AgentLineDecoder.encode(.send(chatID: "c1", text: "hi \"there\""))
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        let decoded = try JSONDecoder().decode(AgentRequest.self, from: line.dropLast())
        XCTAssertEqual(decoded, .send(chatID: "c1", text: "hi \"there\""))
    }

    func testStatusParsing() {
        let running = AgentHostStatus.parse("daemon=running\ndaemonImage=yes\nagentImage=yes\nsocket=unix:///run/user/501/podman/podman.sock\nnotify=yes\n")
        XCTAssertEqual(running.daemon, .running)
        XCTAssertTrue(running.ready && running.daemonImage && running.agentImage && running.notifySecret)
        XCTAssertEqual(running.socketPath, "unix:///run/user/501/podman/podman.sock")

        let exited = AgentHostStatus.parse("daemon=exited\ndaemonImage=yes\nagentImage=no\nsocket=\nnotify=no")
        XCTAssertEqual(exited.daemon, .stopped("exited"))
        XCTAssertFalse(exited.ready)
        XCTAssertFalse(exited.agentImage)

        XCTAssertEqual(AgentHostStatus.parse("").daemon, .missing)
        XCTAssertEqual(AgentHostStatus.parse("daemon=missing").daemon, .missing)
    }

    func testStartDaemonQuotesAndStripsSocketScheme() {
        let settings = AgentModeSettings(orchestrator: .local, orchestratorModel: "qwen 3.6", worker: .claude,
                                         localURL: "http://host.containers.internal:8083/v1")
        let cmd = AgentHostCommands.startDaemon(podman: "/opt/homebrew/bin/podman",
                                                socketPath: "unix:///run/user/501/podman/podman.sock",
                                                settings: settings, hostName: "mac", notify: true)
        XCTAssertTrue(cmd.hasPrefix("'/opt/homebrew/bin/podman' run -d --name sshido-agents"))
        XCTAssertTrue(cmd.contains("-v '/run/user/501/podman/podman.sock:/run/podman.sock'"))
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_ORCHESTRATOR=local'"))
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_ORCHESTRATOR_MODEL=qwen 3.6'"))
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_WORKER_HARNESS=claude'"))
        XCTAssertTrue(cmd.contains("--secret sshido-agents-notify,type=env,target=SSHIDO_NOTIFY_URL"))
        XCTAssertTrue(cmd.hasSuffix("localhost/sshido-agents:latest daemon"))
        let silent = AgentHostCommands.startDaemon(podman: "podman", socketPath: "/s", settings: settings,
                                                   hostName: "mac", notify: false)
        XCTAssertFalse(silent.contains("--secret"))
    }

    func testNotifySecretQuotesURL() {
        let cmd = AgentHostCommands.setNotifySecret(podman: "podman", url: "https://push.sshido.com/n/a'b")
        XCTAssertEqual(cmd, #"printf %s 'https://push.sshido.com/n/a'\''b' | 'podman' secret create --replace sshido-agents-notify -"#)
    }

    func testLoginCommands() {
        XCTAssertNil(AgentHostCommands.login(podman: "podman", harness: .local))
        let claude = AgentHostCommands.login(podman: "podman", harness: .claude) ?? ""
        XCTAssertTrue(claude.contains("-v sshido-auth-claude:/home/agent/.claude"))
        XCTAssertTrue(claude.contains("claude auth login --claudeai"))
        XCTAssertTrue(claude.contains("runuser -u agent"))
        let grok = AgentHostCommands.login(podman: "podman", harness: .grok) ?? ""
        XCTAssertTrue(grok.contains("grok login --device-auth"))
    }

    func testSettingsRoundTrip() throws {
        let suite = "sshido.tests.agentMode.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AgentModeSettingsStore(suiteName: suite)
        XCTAssertEqual(store.load(), .default)
        let saved = AgentModeSettings(enabled: true, hostID: UUID(), orchestrator: .grok, worker: .local,
                                      workerModel: "qwen3.6:35b-instruct", podmanPath: "/usr/bin/podman")
        try store.save(saved)
        XCTAssertEqual(store.load(), saved)
    }

    private func json(_ request: AgentRequest) throws -> [String: Any] {
        let data = try AgentLineDecoder.encode(request).dropLast()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDecodesChatEvents() {
        let chat = #"{"type":"chat","chat":{"id":"c2","title":"crew","createdAt":5}}"#
        let removed = #"{"type":"chatRemoved","chatId":"c2"}"#
        let outputs = feed([chat + "\n" + removed + "\n"])
        XCTAssertEqual(outputs, [
            .event(.chat(AgentChat(id: "c2", title: "crew", createdAt: 5))),
            .event(.chatRemoved("c2")),
        ])
    }

    func testRequestsUseTheDaemonFieldNames() throws {
        let send = try json(.send(chatID: "c1", text: "hi"))
        XCTAssertEqual(send as NSDictionary, ["op": "send", "chatId": "c1", "text": "hi"] as NSDictionary)
        XCTAssertEqual(try json(.createChat(title: "solo")) as NSDictionary,
                       ["op": "createChat", "title": "solo"] as NSDictionary)
        XCTAssertEqual(try json(.deleteChat(id: "c9")) as NSDictionary, ["op": "deleteChat", "chatId": "c9"] as NSDictionary)
        XCTAssertEqual(try json(.hello(since: 3)) as NSDictionary, ["op": "hello", "since": 3] as NSDictionary)
    }

    func testOlderSettingsStillLoad() throws {
        let suite = "sshido.tests.agentMode.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let id = UUID()
        let old = #"{"enabled":true,"hostID":"\#(id.uuidString)","orchestrator":"local","orchestratorModel":"qwen3.6:35b-instruct","worker":"claude","workerModel":"","localURL":"http://h:8083/v1","podmanPath":"/opt/homebrew/bin/podman","pickerModel":"qwen3.6:35b-instruct","hostDirectories":["/Users/me/code"]}"#
        UserDefaults(suiteName: suite)?.set(Data(old.utf8), forKey: AgentModeSettingsStore.key)
        let loaded = AgentModeSettingsStore(suiteName: suite).load()
        XCTAssertEqual(loaded, AgentModeSettings(enabled: true, hostID: id, orchestrator: .local,
                                                 orchestratorModel: "qwen3.6:35b-instruct", worker: .claude,
                                                 localURL: "http://h:8083/v1", podmanPath: "/opt/homebrew/bin/podman",
                                                 hostDirectories: ["/Users/me/code"]))
        XCTAssertEqual(loaded.workerChoice, .fixed)
        XCTAssertEqual(loaded.workerAllowed, [.claude])
    }

    func testStartDaemonPassesWorkerChoiceAndHostFolders() {
        let settings = AgentModeSettings(workerChoice: .orchestrator, workerAllowed: [.claude, .local],
                                         workerLocalModel: "qwen3.6:35b-instruct",
                                         hostDirectories: ["/Users/me/code", "/Users/me/it's"])
        let cmd = AgentHostCommands.startDaemon(podman: "podman", socketPath: "/s", settings: settings, hostName: "h", notify: false)
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_WORKER_CHOICE=orchestrator'"))
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_WORKER_HARNESSES=claude,local'"))
        XCTAssertTrue(cmd.contains("-e 'SSHIDO_WORKER_LOCAL_MODEL=qwen3.6:35b-instruct'"))
        XCTAssertFalse(cmd.contains("PICKER"))
        XCTAssertTrue(cmd.contains(#"-e 'SSHIDO_HOST_DIRS=["/Users/me/code","/Users/me/it'\''s"]'"#), cmd)
        let empty = AgentHostCommands.startDaemon(podman: "podman", socketPath: "/s", settings: .default, hostName: "h", notify: false)
        XCTAssertTrue(empty.contains("-e 'SSHIDO_HOST_DIRS=[]'"))
        let replace = AgentHostCommands.replaceDaemon(podman: "podman", socketPath: "/s", settings: settings, hostName: "h", notify: false)
        XCTAssertTrue(replace.hasPrefix("'podman' rm -f sshido-agents >/dev/null && 'podman' run -d --name sshido-agents"))
    }

    func testHostDirectoryChecks() {
        XCTAssertNotNil(AgentModeSettings.hostDirectoryProblem("code", among: []))
        XCTAssertNotNil(AgentModeSettings.hostDirectoryProblem("/", among: []))
        XCTAssertNotNil(AgentModeSettings.hostDirectoryProblem("/Users/me/code/", among: ["/Users/me/code"]))
        XCTAssertNil(AgentModeSettings.hostDirectoryProblem(" /Users/me/notes ", among: ["/Users/me/code"]))
        XCTAssertEqual(AgentModeSettings.normalizedHostDirectory(" /Users/me/notes/ "), "/Users/me/notes")
        XCTAssertFalse(AgentModeSettings.default.usesLocalEndpoint)
        XCTAssertTrue(AgentModeSettings(orchestrator: .local).usesLocalEndpoint)
        XCTAssertTrue(AgentModeSettings(worker: .local).usesLocalEndpoint)
        XCTAssertFalse(AgentModeSettings(worker: .local, workerChoice: .orchestrator, workerAllowed: [.codex]).usesLocalEndpoint)
        XCTAssertTrue(AgentModeSettings(workerChoice: .orchestrator, workerAllowed: [.codex, .local]).usesLocalEndpoint)
    }

    func testSettingsProblems() {
        XCTAssertNil(AgentModeSettings.default.problem)
        XCTAssertNotNil(AgentModeSettings(orchestrator: .local).problem)
        XCTAssertNil(AgentModeSettings(orchestrator: .local, orchestratorModel: "qwen").problem)
        XCTAssertNotNil(AgentModeSettings(worker: .local).problem)
        XCTAssertNil(AgentModeSettings(worker: .local, workerChoice: .orchestrator).problem)
        XCTAssertNotNil(AgentModeSettings(workerChoice: .orchestrator, workerAllowed: []).problem)
        XCTAssertNotNil(AgentModeSettings(workerChoice: .orchestrator, workerAllowed: [.local]).problem)
        XCTAssertNil(AgentModeSettings(workerChoice: .orchestrator, workerAllowed: [.local], workerLocalModel: "qwen").problem)
    }

    func testAllowingKeepsHarnessOrderAndSignIns() {
        let s = AgentModeSettings(orchestrator: .codex, workerChoice: .orchestrator, workerAllowed: [.claude])
            .allowing(.local, true).allowing(.grok, true).allowing(.claude, false).allowing(.gemini, true)
        XCTAssertEqual(s.workerAllowed, [.gemini, .grok, .local])
        XCTAssertEqual(s.signInHarnesses, [.codex, .gemini, .grok])
        XCTAssertEqual(AgentModeSettings(orchestrator: .claude, worker: .claude).signInHarnesses, [.claude])
        XCTAssertEqual(AgentHarness.frontier, [.claude, .codex, .gemini, .grok])
    }

    func testDecodesAgentWorkRecord() {
        let line = #"{"type":"agent","agent":{"id":"a1","chatId":"c1","name":"writer","role":"worker","harness":"codex","status":"idle","task":"write it","goal":"hello.txt says hi","workStatus":"done","verification":"cat printed hi","verdict":"pass","verdictNote":"checked","container":"sshido-agent-a1","createdAt":1,"updatedAt":2}}"#
        guard case .event(.agent(let a)) = feed([line + "\n"]).first else { return XCTFail("want agent") }
        XCTAssertEqual(a.goal, "hello.txt says hi")
        XCTAssertEqual(a.workStatus, .done)
        XCTAssertEqual(a.verification, "cat printed hi")
        XCTAssertEqual(a.verdict, .pass)
        XCTAssertEqual(a.verdictNote, "checked")
        guard case .event(.agent(let bare)) = feed([orchestratorLine + "\n"]).first else { return XCTFail("want agent") }
        XCTAssertNil(bare.workStatus)
        XCTAssertNil(bare.verdict)
    }

    func testRecordAndDesktopCommands() {
        XCTAssertEqual(AgentHostCommands.log(podman: "podman", agentID: "a1"),
                       "'podman' exec sshido-agents /usr/local/bin/sshido-agents log 'a1'")
        XCTAssertEqual(AgentHostCommands.desktopServe(podman: "podman", container: "sshido-agent-a1"),
                       "'podman' start 'sshido-agent-a1' >/dev/null && 'podman' exec -u agent 'sshido-agent-a1' desktop serve")
        XCTAssertEqual(AgentHostCommands.desktopHostPort(podman: "podman", container: "sshido-agent-a1"),
                       "'podman' port 'sshido-agent-a1' 6080/tcp")
        XCTAssertEqual(AgentHostCommands.parseHostPort("127.0.0.1:41235\n"), 41235)
        XCTAssertEqual(AgentHostCommands.parseHostPort("0.0.0.0:0\n127.0.0.1:5000"), 5000)
        XCTAssertNil(AgentHostCommands.parseHostPort("Error: no such container"))
        XCTAssertNil(AgentHostCommands.parseHostPort(""))
    }

    func testEchoRemovesOnePendingSendFromTheSameChat() {
        let a = AgentPendingSend(id: UUID(), chatId: "c1", text: "go")
        let b = AgentPendingSend(id: UUID(), chatId: "c1", text: "go")
        let other = AgentPendingSend(id: UUID(), chatId: "c2", text: "go")
        let echo = AgentChatMessage(id: 7, chatId: "c1", agentId: nil, author: "you", kind: .user, text: "go", createdAt: 1)
        XCTAssertEqual(AgentPendingSend.removingEcho(of: echo, from: [other, a, b]), [other, b])
        let reply = AgentChatMessage(id: 8, chatId: "c1", agentId: "x", author: "o", kind: .reply, text: "go", createdAt: 1)
        XCTAssertEqual(AgentPendingSend.removingEcho(of: reply, from: [a]), [a])
    }

    func testParsesTrackRecord() {
        let log = "## 2026-09-30T14:50:36Z\n\nSpawned by the orchestrator.\n\nGoal: g\n\n## 2026-09-30T14:51:00Z\n\nStatus: done - ok\n\n## broken\n\n"
        let entries = AgentTrackEntry.parse(log)
        XCTAssertEqual(entries.map(\.body), ["Spawned by the orchestrator.\n\nGoal: g", "Status: done - ok"])
        XCTAssertEqual(entries[0].date, ISO8601DateFormatter().date(from: "2026-09-30T14:50:36Z"))
        XCTAssertEqual(entries[1].heading, "2026-09-30T14:51:00Z")
        XCTAssertEqual(AgentTrackEntry.parse(""), [])
        XCTAssertEqual(AgentTrackEntry.parse("## x\n\nkeeps ## inside a line\n"), [AgentTrackEntry(heading: "x", date: nil, body: "keeps ## inside a line")])
    }
}
