import XCTest
@testable import Morrow

@MainActor
final class MorrowTests: XCTestCase {
    func testRandomPickerRespectsTimeAndEnergyWhenMatchesExist() {
        let model = AppModel()
        let picked = model.pickTask(maxMinutes: 10, energy: .low)
        XCTAssertNotNil(picked)
        XCTAssertLessThanOrEqual(picked?.durationMinutes ?? .max, 10)
        XCTAssertLessThanOrEqual(picked?.energy.rank ?? .max, EnergyLevel.low.rank)
    }

    func testQuickAddCreatesTask() {
        let model = AppModel()
        let initialCount = model.tasks.count
        model.quickAdd("Call Jo tomorrow")
        XCTAssertEqual(model.tasks.count, initialCount + 1)
        XCTAssertEqual(model.tasks.last?.title, "Call Jo tomorrow")
        XCTAssertNotNil(model.tasks.last?.dueDate)
    }
}

