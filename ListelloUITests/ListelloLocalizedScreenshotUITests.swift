import XCTest

final class ListelloLocalizedScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        let language = ProcessInfo.processInfo.environment["LISTELLO_SCREENSHOT_LANGUAGE"] ?? "de"
        let locale = ProcessInfo.processInfo.environment["LISTELLO_SCREENSHOT_LOCALE"] ?? "de_DE"
        app.launchArguments = [
            "--listello-screenshot-ui-test",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testCaptureLocalizedIPadScreens() {
        let projects = app.buttons["screenshots-open-projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 8))

        projects.tap()
        pause()
        capture("03-Projects-and-lists")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).tap()

        let task = app.descendants(matching: .any)["screenshots-task-33333333-3333-3333-3333-333333333333"].firstMatch
        if task.waitForExistence(timeout: 2) {
            task.tap()
        } else {
            app.cells.element(boundBy: 2).tap()
        }
        pause()
        capture("04-Flexible-details")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.18)).tap()

        let sort = app.buttons["screenshots-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        pause()
        capture("05-Sort-your-way")
        sort.tap()

        let random = app.buttons["screenshots-random"]
        XCTAssertTrue(random.waitForExistence(timeout: 5))
        random.tap()
        pause()
        capture("07-Random-pick")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.18)).tap()

        app.buttons["screenshots-tab-schedule"].firstMatch.tap()
        pause()
        capture("01-Build-your-day")
        let addSchedule = app.buttons["screenshots-add-schedule"]
        XCTAssertTrue(addSchedule.waitForExistence(timeout: 5))
        addSchedule.tap()
        app.buttons.element(boundBy: 0).tap()
        pause()
        capture("02-Handle-clashes")

        app.buttons["screenshots-tab-settings"].firstMatch.tap()
        pause()
        capture("06-Make-it-yours")
    }

    private func pause() { RunLoop.current.run(until: Date().addingTimeInterval(1.2)) }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
