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

        drag(
            "task-reorder-11111111-1111-1111-1111-111111111111",
            to: "task-reorder-33333333-3333-3333-3333-333333333333"
        )
        if firstTitle.frame.minY < thirdTitle.frame.minY {
            drag(
                "task-reorder-11111111-1111-1111-1111-111111111111",
                to: "task-reorder-33333333-3333-3333-3333-333333333333"
            )
        }
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

        drag(
            "project-reorder-AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            to: "project-reorder-CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )
        if alphaTitle.frame.minY < gammaTitle.frame.minY {
            drag(
                "project-reorder-AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                to: "project-reorder-CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
            )
        }
        XCTAssertGreaterThan(alphaTitle.frame.minY, gammaTitle.frame.minY)

        relaunchWithoutSeeding()
        openProjects()
        XCTAssertGreaterThan(
            app.staticTexts["Alpha project"].frame.minY,
            app.staticTexts["Gamma project"].frame.minY
        )
    }

    private func drag(_ sourceIdentifier: String, to destinationIdentifier: String) {
        let source = app.descendants(matching: .any)[sourceIdentifier]
        let destination = app.descendants(matching: .any)[destinationIdentifier]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(
            forDuration: 0.8,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
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
