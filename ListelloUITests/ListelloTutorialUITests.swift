import XCTest

final class ListelloTutorialUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--listello-tutorial-ui-test",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB"
        ]
        app.launch()
    }

    func testTutorialCanBeCompletedReplayedSkippedAndStaysDismissed() {
        XCTAssertTrue(app.staticTexts["A simple, flexible home for tasks, lists and plans."].waitForExistence(timeout: 5))

        let expectedMessages = [
            "Type here to add a task or item without leaving your list.",
            "Open the sidebar to create, choose and reorder projects and lists.",
            "Choose how the list is sorted. Random Pick appears beside this when tasks are available.",
            "Add timed tasks or breaks. If something clashes, Listello can shift only the entries that need to move.",
            "Change defaults, appearance and archiving here. You can replay this tutorial whenever you like."
        ]

        let targetControls = [
            app.textFields["Add a task"],
            app.buttons["Open projects"],
            app.buttons["Sort"],
            app.buttons["Add to schedule"],
            app.buttons["Replay tutorial"]
        ]

        for (message, targetControl) in zip(expectedMessages, targetControls) {
            let next = app.buttons["Next"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 3))
            assertHighlightIsVerticallyAligned(with: targetControl)
        }

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3))
        settingsTab.tap()

        let replay = app.buttons["Replay tutorial"]
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        replay.tap()
        XCTAssertTrue(app.staticTexts["A simple, flexible home for tasks, lists and plans."].waitForExistence(timeout: 3))

        app.buttons["Skip"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        XCTAssertFalse(app.staticTexts["A simple, flexible home for tasks, lists and plans."].waitForExistence(timeout: 2))
    }

    private func assertHighlightIsVerticallyAligned(
        with target: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let highlight = app.descendants(matching: .any)["tutorial-highlight"]
        XCTAssertTrue(target.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(highlight.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertLessThanOrEqual(
            abs(highlight.frame.midY - target.frame.midY),
            3,
            "Tutorial highlight must share the target control's vertical centre",
            file: file,
            line: line
        )
    }
}
