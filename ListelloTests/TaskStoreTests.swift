import XCTest
@testable import Listello

@MainActor
final class TaskStoreTests: XCTestCase {
    private var storageURL: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listello-tests-\(UUID().uuidString).json")
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL)
        super.tearDown()
    }

    func testTasksStartUnscheduledWithDefaultDuration() {
        let store = makeStore()
        let task = store.addTask(title: "Buy milk")

        XCTAssertEqual(task?.title, "Buy milk")
        XCTAssertNil(task?.scheduledAt)
        XCTAssertEqual(task?.expectedDurationMinutes, 30)
        XCTAssertEqual(store.activeTasks.count, 1)
        XCTAssertTrue(store.tasks(on: Date()).isEmpty)
    }

    func testExplicitlyRemovingDurationSurvivesPersistence() async throws {
        var store: TaskStore? = makeStore()
        var task = try XCTUnwrap(store?.addTask(title: "Open-ended task"))
        task.expectedDurationMinutes = nil
        await store?.saveTask(task)
        store = nil

        let restored = makeStore()
        XCTAssertNil(restored.activeTasks.first?.expectedDurationMinutes)
    }

    func testProjectsFilterTasksWithoutMakingProjectsCompulsory() {
        let store = makeStore()
        let website = store.addProject(name: "Create website", color: .sky)!
        store.addTask(title: "Login form", projectID: website.id)
        store.addTask(title: "Buy milk")

        let websiteTasks = store.filteredTasks(mode: .active, query: "", projectID: website.id)
        XCTAssertEqual(websiteTasks.map(\.title), ["Login form"])
        XCTAssertEqual(store.filteredTasks(mode: .active, query: "", projectID: nil).count, 2)
    }

    func testReorderingAFilteredProjectPreservesItsOrder() {
        let store = makeStore()
        let project = store.addProject(name: "Website", color: .teal)!
        store.addTask(title: "Login", projectID: project.id)
        store.addTask(title: "Home", projectID: project.id)
        store.addTask(title: "Unassigned")

        let visible = store.filteredTasks(mode: .active, query: "", projectID: project.id)
        store.moveTasks(from: IndexSet(integer: 0), to: 2, within: visible)

        XCTAssertEqual(
            store.filteredTasks(mode: .active, query: "", projectID: project.id).map(\.title),
            ["Home", "Login"]
        )
    }

    func testScheduleConflictSuggestsTheNextFreeTime() async {
        let store = makeStore()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let ten = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!

        await store.saveTask(TaskItem(title: "Existing", scheduledAt: nine, expectedDurationMinutes: 60))
        let proposed = TaskItem(
            title: "New",
            scheduledAt: calendar.date(byAdding: .minute, value: 30, to: nine),
            expectedDurationMinutes: 30
        )
        let conflict = store.scheduleConflict(for: proposed, calendarEntries: [])

        XCTAssertEqual(conflict?.conflictingTitle, "Existing")
        XCTAssertEqual(conflict?.suggestedStart, ten)
    }

    func testCalendarImportsSkipExistingEvents() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEntry(
            id: "event-1",
            title: "Design review",
            notes: "",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            calendarTitle: "Work",
            colorHex: "#38BDB2"
        )

        XCTAssertEqual(store.importCalendarEntries([event]), 1)
        XCTAssertEqual(store.importCalendarEntries([event]), 0)
        XCTAssertEqual(store.activeTasks.first?.expectedDurationMinutes, 60)
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

    func testSuggestionUsesOnlyTheVisibleTasks() {
        let store = makeStore()
        let first = store.addTask(title: "Visible")!
        store.addTask(title: "Hidden")

        XCTAssertEqual(store.suggestedTask(from: [first])?.id, first.id)
    }

    func testStatePersistsTasksAndProjects() {
        var store: TaskStore? = makeStore()
        let project = store?.addProject(name: "Home", color: .coral)
        store?.addTask(title: "Remember this", projectID: project?.id)
        store = nil

        let restored = makeStore()
        XCTAssertEqual(restored.projects.map(\.name), ["Home"])
        XCTAssertEqual(restored.activeTasks.map(\.title), ["Remember this"])
        XCTAssertEqual(restored.activeTasks.first?.projectID, restored.projects.first?.id)
    }

    private func makeStore() -> TaskStore {
        TaskStore(storageURL: storageURL, calendar: calendar, managesNotifications: false)
    }
}
