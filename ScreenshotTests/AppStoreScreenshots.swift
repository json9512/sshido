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
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
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

    private func button(startingWith prefix: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        _ = matches.firstMatch.waitForExistence(timeout: 20)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

    private func trustHostKeyIfAsked() {
        let trust = app.buttons["Trust & connect"]
        if trust.waitForExistence(timeout: 8) { trust.tap() }
    }

    private func dismissKeyboard() {
        let hide = app.buttons["Hide keyboard"].firstMatch
        if hide.waitForExistence(timeout: 2) { hide.tap() }
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let current = field.value as? String ?? ""
        guard current != value else { return }
        tap(field)
        let stale = current == field.placeholderValue ? 0 : current.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: stale) + value)
    }

    private func localModelFields() -> XCUIElementQuery {
        app.textFields.matching(identifier: "Local model, e.g. qwen3.6:35b")
    }

    private func openSettings(_ entry: String) {
        tap(app.buttons["Settings"].firstMatch)
        tap(button(startingWith: entry))
    }

    func test1SetUpHostAndAgentMode() throws {
        let pem = try String(contentsOfFile: try setting("SSHIDO_SCREENSHOT_KEY"), encoding: .utf8)
        let model = try setting("SSHIDO_SCREENSHOT_MODEL")

        sleep(2)
        try capture("design-home-empty")
        tap(app.buttons["Add server"].firstMatch)
        tap(app.buttons["New key"])
        type("MacBook key", into: app.textFields["Label"])
        type(pem, into: app.textViews.firstMatch)
        dismissKeyboard()
        tap(app.navigationBars["New key"].buttons["Save"])
        sleep(1)
        try capture("design-key-installed")
        tap(app.navigationBars["Install key"].buttons["Save"])
        type("MacBook", into: app.textFields["Name"])
        type(try setting("SSHIDO_SCREENSHOT_HOST"), into: app.textFields["Host"])
        type(try setting("SSHIDO_SCREENSHOT_USER"), into: app.textFields["User"])
        dismissKeyboard()
        try capture("design-add-server")
        tap(app.navigationBars["New server"].buttons["Save"])
        trustHostKeyIfAsked()
        XCTAssertTrue(app.staticTexts["MacBook"].firstMatch.waitForExistence(timeout: 30))

        openSettings("Agents")
        let toggle = app.switches.containing(NSPredicate(format: "label BEGINSWITH 'Agents'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" { toggle.switches.firstMatch.tap() }
        tap(button(startingWith: "Host"))
        tap(app.buttons["MacBook"].firstMatch)
        tap(app.segmentedControls.element(boundBy: 0).buttons["Local"])
        replace(localModelFields().element(boundBy: 0), with: model)
        dismissKeyboard()
        tap(app.segmentedControls.element(boundBy: 1).buttons["Local"])
        replace(localModelFields().element(boundBy: 1), with: model)
        dismissKeyboard()
        let apply = app.buttons["Apply settings"]
        for _ in 0..<8 where !(apply.exists && apply.isHittable) { app.swipeUp() }
        tap(apply)
        trustHostKeyIfAsked()
        let running = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Daemon running'")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while !running.exists && Date() < deadline {
            app.swipeUp()
            sleep(3)
        }
        XCTAssertTrue(running.exists, "the daemon did not report running")
        try capture("design-agents-settings")
    }

    func test2CaptureSettings() throws {
        tap(app.buttons["Settings"].firstMatch)
        sleep(2)
        try capture("design-settings")
        tap(button(startingWith: "Agents"))
        tap(app.segmentedControls.element(boundBy: 1).buttons["Auto"])
        let claude = app.switches["Claude Code"].firstMatch
        if claude.waitForExistence(timeout: 5), claude.value as? String != "1" { claude.switches.firstMatch.tap() }
        let local = app.switches["Local model"].firstMatch
        if local.waitForExistence(timeout: 5), local.value as? String != "1" { local.switches.firstMatch.tap() }
        let fields = localModelFields()
        replace(fields.element(boundBy: max(fields.count - 1, 0)), with: try setting("SSHIDO_SCREENSHOT_MODEL"))
        dismissKeyboard()
        app.swipeDown()
        sleep(1)
        try capture("settings-models")
        tap(app.segmentedControls.element(boundBy: 1).buttons["Local"])
        app.navigationBars.buttons.element(boundBy: 0).tap()

        for (entry, name) in [("Notifications", "design-notifications"), ("Servers & keys", "design-servers"),
                              ("Appearance", "design-appearance"), ("Set up a host", "design-agent-guide")] {
            tap(button(startingWith: entry))
            sleep(2)
            try capture(name)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func test3CaptureAgentChat() throws {
        let chatTitle = try setting("SSHIDO_SCREENSHOT_CHAT")
        sleep(3)
        try capture("design-home")
        tap(button(startingWith: "Agents"))
        let chat = button(startingWith: chatTitle)
        XCTAssertTrue(chat.waitForExistence(timeout: 60))
        try capture("chat-list")
        chat.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 30))
        sleep(4)
        try capture("chat-bottom")
        for step in 1...4 {
            app.swipeDown(velocity: .slow)
            sleep(1)
            try capture("chat-up-\(step)")
        }

        let chip = app.buttons.containing(NSPredicate(format: "label CONTAINS 'verdict pass' AND NOT (label BEGINSWITH 'orchestrator')")).firstMatch
        tap(chip, timeout: 30)
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

    func test5ReviewChat() throws {
        tap(button(startingWith: "Agents"))
        let chat = button(startingWith: try setting("SSHIDO_SCREENSHOT_CHAT"))
        XCTAssertTrue(chat.waitForExistence(timeout: 60))
        chat.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 30))
        sleep(5)
        try capture("review-bottom")
        for step in 1...6 {
            app.swipeDown(velocity: .slow)
            sleep(1)
            try capture("review-up-\(step)")
        }
    }

    func test6ReviewModelPicker() throws {
        openSettings("Agents")
        let picker = button(startingWith: "Model")
        XCTAssertTrue(picker.waitForExistence(timeout: 60), "the model list did not load")
        sleep(1)
        try capture("review-models")
        picker.tap()
        sleep(2)
        try capture("review-models-menu")
        app.swipeDown()
    }

    func test4CaptureTerminal() throws {
        tap(app.staticTexts["MacBook"].firstMatch)
        sleep(2)
        try capture("design-sessions")
        tap(app.buttons["New session"].firstMatch)
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
