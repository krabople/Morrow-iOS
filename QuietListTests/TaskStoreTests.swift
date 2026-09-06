import XCTest
@testable import QuietList

@MainActor
final class TaskStoreTests: XCTestCase {
    private var storageURL: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiet-list-tests-\(UUID().uuidString).json")
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL)
        super.tearDown()
    }

    func testTasksStartUnscheduled() {
        let store = makeStore()
        let task = store.addTask(title: "Buy milk")

        XCTAssertEqual(task?.title, "Buy milk")
        XCTAssertNil(task?.scheduledAt)
        XCTAssertEqual(store.activeTasks.count, 1)
        XCTAssertTrue(store.tasks(on: Date()).isEmpty)
    }

    func testScheduleReturnsOnlyTasksForSelectedDay() async {
        let store = makeStore()
        let selectedDay = Date(timeIntervalSince1970: 1_800_000_000)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDay)!

        var first = TaskItem(title: "Morning walk", scheduledAt: selectedDay)
        first.scheduledAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay)
        await store.saveTask(first)
        await store.saveTask(TaskItem(title: "Tomorrow", scheduledAt: nextDay))

        XCTAssertEqual(store.tasks(on: selectedDay).map(\.title), ["Morning walk"])
    }

    func testCompletingAndRestoringTask() {
        let store = makeStore()
        let task = store.addTask(title: "Reply to Sam")!

        store.toggleCompleted(task)
        XCTAssertTrue(store.activeTasks.isEmpty)
        XCTAssertEqual(store.completedTasks.count, 1)

        store.toggleCompleted(store.completedTasks[0])
        XCTAssertEqual(store.activeTasks.count, 1)
        XCTAssertTrue(store.completedTasks.isEmpty)
    }

    func testSuggestionReturnsAnActiveTask() {
        let store = makeStore()
        let task = store.addTask(title: "Only choice")!

        XCTAssertEqual(store.suggestedTask()?.id, task.id)
        store.toggleCompleted(task)
        XCTAssertNil(store.suggestedTask())
    }

    func testStatePersists() {
        var store: TaskStore? = makeStore()
        store?.addTask(title: "Remember this")
        store = nil

        let restored = makeStore()
        XCTAssertEqual(restored.activeTasks.map(\.title), ["Remember this"])
    }

    private func makeStore() -> TaskStore {
        TaskStore(storageURL: storageURL, calendar: calendar, managesNotifications: false)
    }
}
