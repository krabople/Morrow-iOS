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

    func testArchiveAllRestoreAndDeleteAll() {
        let store = makeStore()
        store.addTask(title: "First")
        let second = store.addTask(title: "Second")!
        store.toggleCompleted(second)

        XCTAssertEqual(store.archiveAllTasks(), 2)
        XCTAssertTrue(store.activeTasks.isEmpty)
        XCTAssertTrue(store.completedTasks.isEmpty)
        XCTAssertEqual(store.archivedTasks.count, 2)

        store.restoreAllArchivedTasks()
        XCTAssertEqual(store.activeTasks.count, 2)
        XCTAssertTrue(store.archivedTasks.isEmpty)

        store.archiveAllTasks()
        store.deleteAllArchivedTasks()
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testCustomDurationChoicesAndDefaultsPersist() {
        var store: TaskStore? = makeStore()
        store?.setDurationOptions([5, 25, 25, 2_000])
        store?.setDefaultDuration(5)
        store?.setAppearance(.dark)
        store?.setNotifyNewScheduledTasks(true)
        store = nil

        let restored = makeStore()
        XCTAssertEqual(restored.preferences.durationOptions, [5, 25])
        XCTAssertEqual(restored.preferences.defaultDurationMinutes, 5)
        XCTAssertEqual(restored.preferences.appearance, .dark)
        XCTAssertTrue(restored.preferences.notifyNewScheduledTasks)
        XCTAssertEqual(restored.addTask(title: "Five minute job")?.expectedDurationMinutes, 5)
    }

    func testCompletedTasksAutomaticallyMoveToArchive() async {
        let store = makeStore()
        let completedAt = calendar.date(byAdding: .day, value: -8, to: Date())!
        await store.saveTask(TaskItem(title: "Old completed task", completedAt: completedAt))

        store.setCompletedArchiveDelayDays(7)

        XCTAssertTrue(store.completedTasks.isEmpty)
        XCTAssertEqual(store.archivedTasks.map(\.title), ["Old completed task"])
    }

    func testRecurringTaskAppearsOnFutureDatesAndAdvancesWhenDone() async {
        let store = makeStore()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let followingDay = calendar.date(byAdding: .day, value: 1, to: start)!
        await store.saveTask(TaskItem(
            title: "Daily review",
            scheduledAt: start,
            calendarEventIdentifier: "calendar-event",
            recurrence: .daily
        ))

        XCTAssertEqual(store.tasks(on: start).map(\.title), ["Daily review"])
        XCTAssertEqual(store.tasks(on: followingDay).map(\.title), ["Daily review"])

        store.toggleCompleted(store.activeTasks[0])

        XCTAssertTrue(store.activeTasks.isEmpty)
        XCTAssertEqual(store.tasks(on: followingDay).map(\.title), ["Daily review"])
        XCTAssertTrue(store.completedTasks.isEmpty)
        XCTAssertNil(store.tasks(on: followingDay).first?.calendarEventIdentifier)
    }

    func testDeletingOneFutureRecurringOccurrenceKeepsTheSeries() async {
        let store = makeStore()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)!
        let second = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
        let third = calendar.date(byAdding: .weekOfYear, value: 2, to: start)!
        await store.saveTask(TaskItem(title: "Weekly planning", scheduledAt: start, recurrence: .weekly))

        let secondOccurrence = try! XCTUnwrap(store.tasks(on: second).first)
        store.deleteRecurringOccurrence(secondOccurrence)

        XCTAssertEqual(store.tasks(on: start).count, 1)
        XCTAssertTrue(store.tasks(on: second).isEmpty)
        XCTAssertEqual(store.tasks(on: third).count, 1)
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
