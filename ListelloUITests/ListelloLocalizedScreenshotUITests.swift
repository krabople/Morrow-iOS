import XCTest

final class ListelloLocalizedScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var usesRightToLeftLayout = false

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // GitHub Actions replaces these placeholders before building the test
        // bundle. Custom shell environment variables are not reliably forwarded
        // into the simulator-hosted UI test process.
        let language = "__SCREENSHOT_LANGUAGE__"
        let locale = "__SCREENSHOT_LOCALE__"
        usesRightToLeftLayout = ["ar"].contains(language)
        app.launchArguments = [
            "--listello-screenshot-ui-test",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
    }

    func testCaptureCoreLocalizedIPadScreens() {
        let projects = app.buttons["screenshots-open-projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 8))

        let random = app.buttons["screenshots-random"]
        XCTAssertTrue(random.waitForExistence(timeout: 5))
        random.tap()
        XCTAssertTrue(app.staticTexts["screenshots-random-title"].waitForExistence(timeout: 5))
        pause()
        capture("07-Random-pick")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.18)).tap()

        projects.tap()
        pause()
        capture("03-Projects-and-lists")
        let sidebarDismissX: CGFloat = usesRightToLeftLayout ? 0.18 : 0.82
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: sidebarDismissX, dy: 0.5)).tap()

        let task = app.staticTexts["screenshots-task-33333333-3333-3333-3333-333333333333"].firstMatch
        if task.waitForExistence(timeout: 2) {
            task.tap()
        } else {
            app.cells.element(boundBy: 2).tap()
        }
        pause()
        capture("04-Flexible-details")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.18)).tap()

        app.buttons["screenshots-tab-schedule"].firstMatch.tap()
        pause()
        capture("01-Build-your-day")

        app.buttons["screenshots-tab-settings"].firstMatch.tap()
        pause()
        capture("06-Make-it-yours")
    }

    func testCaptureConflictScreen() {
        let scheduleTab = app.buttons["screenshots-tab-schedule"].firstMatch
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 8))
        scheduleTab.tap()
        pause()
        let addSchedule = app.buttons["screenshots-add-schedule"]
        XCTAssertTrue(addSchedule.waitForExistence(timeout: 5))
        addSchedule.tap()
        let addTask = app.buttons["screenshots-add-scheduled-task"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 5))
        addTask.tap()
        let saveTask = app.buttons["screenshots-save-task"]
        XCTAssertTrue(saveTask.waitForExistence(timeout: 5))
        saveTask.tap()
        pause()
        capture("02-Handle-clashes")
    }

    func testCaptureSortScreen() {
        let sort = app.buttons["screenshots-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 8))
        sort.tap()
        pause()
        capture("05-Sort-your-way")
    }

    private func pause() { RunLoop.current.run(until: Date().addingTimeInterval(1.2)) }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

