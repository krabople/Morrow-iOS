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

    func testListsDefaultToHiddenAndItemsDefaultToNoEstimate() {
        let store = makeStore()
        let watchList = store.addProject(name: "Movies", color: .violet, kind: .list)!
        let item = store.addTask(
            title: "The Third Man",
            projectID: watchList.id,
            usesDefaultDuration: false
        )

        XCTAssertTrue(watchList.hidesFromAllTasks)
        XCTAssertNil(item?.expectedDurationMinutes)
        XCTAssertTrue(store.activeTasks.isEmpty)
        XCTAssertEqual(
            store.filteredTasks(mode: .active, query: "", projectID: watchList.id).map(\.title),
            ["The Third Man"]
        )
    }

    func testProjectVisibilityAndDeletionChoices() {
        let store = makeStore()
        let privateProject = store.addProject(
            name: "Private",
            color: .indigo,
            hidesFromAllTasks: true
        )!
        store.addTask(title: "Secret task", projectID: privateProject.id)
        store.deleteProject(privateProject, disposition: .archiveContents)

        XCTAssertEqual(store.archivedTasks.map(\.title), ["Secret task"])

        let sharedProject = store.addProject(name: "Shared", color: .green)!
        store.addTask(title: "Visible task", projectID: sharedProject.id)
        store.deleteProject(sharedProject, disposition: .keepUnassigned)

        XCTAssertEqual(store.activeTasks.map(\.title), ["Visible task"])
        XCTAssertNil(store.activeTasks.first?.projectID)
    }

    func testTasksAndProjectsCanBeReordered() {
        let store = makeStore()
        store.addTask(title: "First")
        store.addTask(title: "Second")
        store.addTask(title: "Third")
        store.moveTasks(IndexSet(integer: 0), to: 3, within: store.activeTasks)
        XCTAssertEqual(store.activeTasks.map(\.title), ["Second", "Third", "First"])

        store.addProject(name: "Alpha", color: .teal)
        store.addProject(name: "Beta", color: .sky)
        store.addProject(name: "Gamma", color: .amber)
        store.moveProjects(IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.orderedProjects.map(\.name), ["Gamma", "Alpha", "Beta"])
    }

    func testReminderImportUsesDestinationTerminologyDefaults() {
        let store = makeStore()
        let list = store.addProject(name: "Reading", color: .mint, kind: .list)!
        let reminders = [ImportedReminder(
            title: "A book",
            notes: "From a friend",
            dueDate: nil,
            isImportant: true
        )]

        XCTAssertEqual(store.importReminders(reminders, into: list), 1)
        let imported = store.filteredTasks(mode: .active, query: "", projectID: list.id).first
        XCTAssertEqual(imported?.notes, "From a friend")
        XCTAssertTrue(imported?.isImportant == true)
        XCTAssertNil(imported?.expectedDurationMinutes)
    }

    func testLegacyProjectsRemainVisibleProjects() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id.uuidString)","name":"Legacy","color":"teal"}
        """.utf8)
        let project = try JSONDecoder().decode(ProjectItem.self, from: data)

        XCTAssertEqual(project.kind, .project)
        XCTAssertFalse(project.hidesFromAllTasks)
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

    func testSuggestedScheduleStartsWhenMostRecentlyAddedTaskFinishes() async {
        let store = makeStore()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: tomorrow)!
        await store.saveTask(TaskItem(
            title: "Added first",
            createdAt: Date(timeIntervalSince1970: 100),
            scheduledAt: eleven,
            expectedDurationMinutes: 30
        ))
        await store.saveTask(TaskItem(
            title: "Added most recently",
            createdAt: Date(timeIntervalSince1970: 200),
            scheduledAt: nine,
            expectedDurationMinutes: 45
        ))

        XCTAssertEqual(
            store.suggestedScheduleTime(on: tomorrow),
            calendar.date(byAdding: .minute, value: 45, to: nine)
        )
    }

    func testBreaksPersistAndBlockScheduleTime() async {
        var store: TaskStore? = makeStore()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow)!
        let lunch = ScheduleBreakItem(title: "Lunch", startDate: noon, durationMinutes: 60)
        store?.saveBreak(lunch)

        let proposed = TaskItem(title: "Call", scheduledAt: noon, expectedDurationMinutes: 30)
        let conflict = store?.scheduleConflict(for: proposed, calendarEntries: [])
        XCTAssertEqual(conflict?.conflictingTitle, "Lunch")
        XCTAssertEqual(
            conflict?.suggestedStart,
            calendar.date(byAdding: .hour, value: 1, to: noon)
        )

        store = nil
        let restored = makeStore()
        XCTAssertEqual(restored.breaks(on: tomorrow), [lunch])
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

final class LocalizationTests: XCTestCase {
    private let completeLocalizations = [
        "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"
    ]

    func testEverySupportedLanguageHasEveryAppString() throws {
        let resources = repositoryRoot.appendingPathComponent("Listello/Resources", isDirectory: true)
        let english = try stringsDictionary(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        XCTAssertGreaterThan(english.count, 150)

        for locale in completeLocalizations {
            let translations = try stringsDictionary(
                at: resources.appendingPathComponent("\(locale).lproj/Localizable.strings")
            )
            XCTAssertEqual(
                Set(translations.keys),
                Set(english.keys),
                "\(locale) must contain the complete Listello string set"
            )

            let info = try stringsDictionary(
                at: resources.appendingPathComponent("\(locale).lproj/InfoPlist.strings")
            )
            XCTAssertNotNil(info["CFBundleDisplayName"])
            XCTAssertNotNil(info["NSCalendarsFullAccessUsageDescription"])
            XCTAssertNotNil(info["NSRemindersFullAccessUsageDescription"])
            XCTAssertNotNil(info["NSUserNotificationsUsageDescription"])
        }
    }

    func testDynamicTranslationPlaceholdersArePreserved() throws {
        let resources = repositoryRoot.appendingPathComponent("Listello/Resources", isDirectory: true)
        let english = try stringsDictionary(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let dynamicKeys = [
            "add_to_list", "add_to_project", "archived_on", "calendar_name", "delete_project_named",
            "duration_minutes", "imported_reminders_summary", "items_in_list", "keep_time",
            "one_item_in_list", "one_open_task_in_project", "open_tasks_in_project",
            "remove_duration", "schedule_conflict_message",
            "to_time", "today_at_time", "tomorrow_at_time", "use_time"
        ]

        for locale in completeLocalizations {
            let translations = try stringsDictionary(
                at: resources.appendingPathComponent("\(locale).lproj/Localizable.strings")
            )
            for key in dynamicKeys {
                XCTAssertEqual(
                    placeholderCount(in: translations[key] ?? ""),
                    placeholderCount(in: english[key] ?? ""),
                    "\(locale) must preserve the format placeholder for \(key)"
                )
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func stringsDictionary(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        return try XCTUnwrap(object as? [String: String], "Invalid strings file: \(url.path)")
    }

    private func placeholderCount(in value: String) -> Int {
        value.components(separatedBy: "%@").count - 1
            + value.components(separatedBy: "%d").count - 1
    }
}
