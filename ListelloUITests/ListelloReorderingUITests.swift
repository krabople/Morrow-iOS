import XCTest

final class ListelloReorderingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--listello-reordering-ui-test"]
        app.launch()
    }

    func testTaskHandleReordersAndPersists() {
        let firstTitle = app.staticTexts["First task"]
        let thirdTitle = app.staticTexts["Third task"]
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(thirdTitle.exists)

        app.buttons["reorder-tasks-button"].tap()
        dragRow(from: firstTitle, to: thirdTitle, trailingX: app.frame.maxX - 24)
        XCTAssertGreaterThan(firstTitle.frame.minY, thirdTitle.frame.minY)

        relaunchWithoutSeeding()
        XCTAssertGreaterThan(
            app.staticTexts["First task"].frame.minY,
            app.staticTexts["Third task"].frame.minY
        )
    }

    func testProjectHandleReordersAndPersists() {
        openProjects()
        let alphaTitle = app.staticTexts["Alpha project"]
        let gammaTitle = app.staticTexts["Gamma project"]
        XCTAssertTrue(alphaTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(gammaTitle.exists)

        app.buttons["reorder-projects-button"].tap()
        dragRow(from: alphaTitle, to: gammaTitle, trailingX: min(332, app.frame.maxX - 24))
        XCTAssertGreaterThan(alphaTitle.frame.minY, gammaTitle.frame.minY)

        relaunchWithoutSeeding()
        openProjects()
        XCTAssertGreaterThan(
            app.staticTexts["Alpha project"].frame.minY,
            app.staticTexts["Gamma project"].frame.minY
        )
    }

    private func dragRow(from source: XCUIElement, to destination: XCUIElement, trailingX: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: trailingX, dy: source.frame.midY))
        let end = origin.withOffset(CGVector(dx: trailingX, dy: destination.frame.midY))
        start.press(forDuration: 0.15, thenDragTo: end)
    }

    private func openProjects() {
        let button = app.buttons["Open projects"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func relaunchWithoutSeeding() {
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["First task"].waitForExistence(timeout: 5))
    }
}

