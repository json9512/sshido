import XCTest

final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-sshido.privacyAccepted", "YES",
            "-sshido.onboardingCompleted", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    private func setting(_ key: String) throws -> String {
        try XCTUnwrap(env[key], "set \(key) for the screenshot run (TEST_RUNNER_\(key) with xcodebuild)")
    }

    private func capture(_ name: String) throws {
        let dir = URL(fileURLWithPath: try setting("SSHIDO_SCREENSHOT_DIR"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)", file: file, line: line)
        element.tap()
    }

    private func type(_ text: String, into element: XCUIElement) {
        tap(element)
        element.typeText(text)
    }

    private func trustHostKeyIfAsked() {
        let trust = app.buttons["Trust & connect"]
        if trust.waitForExistence(timeout: 8) { trust.tap() }
    }

    private func waitForLog(_ text: String, timeout: TimeInterval) {
        let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: timeout), "no setup log line containing \(text)")
    }

    func test1SetUpHostAndAgentMode() throws {
        let pem = try String(contentsOfFile: try setting("SSHIDO_SCREENSHOT_KEY"), encoding: .utf8)
        let model = try setting("SSHIDO_SCREENSHOT_MODEL")

        tap(app.buttons["Add"].firstMatch)
        tap(app.buttons["Add new key…"])
        type("MacBook key", into: app.textFields["e.g. MacBook id_ed25519"])
        type(pem, into: app.textViews.firstMatch)
        tap(app.buttons["Import"])
        tap(app.buttons["Done"])
        type("MacBook", into: app.textFields["Name"])
        type(try setting("SSHIDO_SCREENSHOT_HOST"), into: app.textFields["Host"])
        type(try setting("SSHIDO_SCREENSHOT_USER"), into: app.textFields["Username"])
        tap(app.buttons["Save"])
        trustHostKeyIfAsked()

        tap(app.buttons["gearshape"].firstMatch)
        let toggle = app.switches["Agent mode"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" { toggle.switches.firstMatch.tap() }
        tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Agent mode'")).element(boundBy: 0))

        tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Agents host'")).firstMatch)
        tap(app.buttons["MacBook"].firstMatch)
        let local = app.segmentedControls.element(boundBy: 0).buttons["Local"]
        tap(local)
        type(model, into: app.textFields["Local model name, e.g. qwen3.6:35b"].firstMatch)
        tap(app.segmentedControls.element(boundBy: 1).buttons["Local"])
        type(model, into: app.textFields.matching(identifier: "Local model name, e.g. qwen3.6:35b").element(boundBy: 1))
        app.swipeUp()
        app.swipeUp()
        tap(app.buttons["Apply settings"])
        trustHostKeyIfAsked()
        waitForLog("Daemon running", timeout: 180)
    }

    func test2CaptureSettings() throws {
        tap(app.buttons["gearshape"].firstMatch)
        tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Agent mode'")).element(boundBy: 0))
        XCTAssertTrue(app.segmentedControls.element(boundBy: 1).waitForExistence(timeout: 10))
        tap(app.segmentedControls.element(boundBy: 1).buttons["Auto"])
        let claude = app.switches["Claude Code"].firstMatch
        if claude.waitForExistence(timeout: 5), claude.value as? String != "1" { claude.switches.firstMatch.tap() }
        let localToggle = app.switches["Local model"].firstMatch
        if localToggle.waitForExistence(timeout: 5), localToggle.value as? String != "1" { localToggle.switches.firstMatch.tap() }
        let fields = app.textFields.matching(identifier: "Local model name, e.g. qwen3.6:35b")
        let field = fields.element(boundBy: max(fields.count - 1, 0))
        let model = try setting("SSHIDO_SCREENSHOT_MODEL")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let current = field.value as? String ?? ""
        if current != model {
            tap(field)
            let stale = current.hasPrefix("Local model name") ? 0 : current.count
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: stale) + model)
        }
        app.navigationBars.staticTexts["Agent mode"].firstMatch.tap()
        let hideKeys = app.keyboards.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hide' OR label CONTAINS[c] 'dismiss'"))
        if app.keyboards.count > 0, hideKeys.count > 0 { hideKeys.firstMatch.tap() }
        sleep(1)
        try capture("settings-models")
        tap(app.segmentedControls.element(boundBy: 1).buttons["Local"])
    }

    func test3CaptureAgentChat() throws {
        let chatTitle = try setting("SSHIDO_SCREENSHOT_CHAT")
        tap(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Agent chat'")).element(boundBy: 0))
        let chat = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", chatTitle)).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 60))
        try capture("chat-list")
        chat.tap()
        XCTAssertTrue(app.textFields["Message the orchestrator"].waitForExistence(timeout: 30))
        sleep(4)
        try capture("chat-bottom")
        for step in 1...4 {
            app.swipeDown(velocity: .slow)
            sleep(1)
            try capture("chat-up-\(step)")
        }

        let chip = app.buttons.containing(NSPredicate(format: "label CONTAINS 'verdict pass' AND NOT (label BEGINSWITH 'orchestrator')")).firstMatch
        tap(chip, timeout: 30)
        XCTAssertTrue(app.staticTexts["Work record"].waitForExistence(timeout: 20) || app.staticTexts["WORK RECORD"].waitForExistence(timeout: 5))
        sleep(4)
        try capture("agent-card")
        app.swipeUp()
        sleep(1)
        try capture("agent-card-track")

        let watch = app.buttons["Watch its desktop"]
        for _ in 0..<20 where !(watch.exists && watch.isHittable) { app.swipeUp() }
        tap(watch)
        sleep(12)
        try capture("agent-desktop")
    }

    func test4CaptureTerminal() throws {
        tap(app.staticTexts["MacBook"].firstMatch)
        tap(app.buttons.containing(NSPredicate(format: "label CONTAINS 'New session'")).firstMatch)
        trustHostKeyIfAsked()
        sleep(8)
        let keyboardToggle = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'keyboard' AND NOT (label CONTAINS[c] 'next')")).firstMatch
        if app.keyboards.count > 0 {
            app.typeText("tmux set status-right ' #{session_name} ' >/dev/null; clear; cd \(try setting("SSHIDO_SCREENSHOT_REPO")) && git log --oneline -24 | cut -c1-52\n")
        } else {
            sleep(20)
        }
        sleep(4)
        if app.keyboards.count > 0 { keyboardToggle.tap() }
        sleep(3)
        try capture("terminal")
    }
}
