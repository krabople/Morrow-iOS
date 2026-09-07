import Combine
import Foundation
import UserNotifications

private enum ShiftableScheduleItem {
    case task(TaskItem)
    case scheduleBreak(ScheduleBreakItem)
}

private struct ShiftableScheduleSlot {
    let item: ShiftableScheduleItem
    let start: Date
    let end: Date
}

private struct OccupiedScheduleSlot {
    let start: Date
    let end: Date
}

private struct ScheduledTaskMove {
    let occurrence: TaskItem
    let newStart: Date
}

private struct ScheduledBreakMove {
    let scheduleBreak: ScheduleBreakItem
    let newStart: Date
}

private struct ScheduleShiftPlan {
    var taskMoves: [ScheduledTaskMove] = []
    var breakMoves: [ScheduledBreakMove] = []

    var isEmpty: Bool { taskMoves.isEmpty && breakMoves.isEmpty }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var projects: [ProjectItem] = []
    @Published private(set) var scheduleBreaks: [ScheduleBreakItem] = []
    @Published private(set) var notificationDayKeys: Set<String> = []
    @Published private(set) var preferences = ListelloPreferences()

    private let calendar: Calendar
    private let storageURL: URL
    private let notificationCenter: UNUserNotificationCenter
    private let managesNotifications: Bool

    init(
        storageURL: URL? = nil,
        calendar: Calendar = .current,
        notificationCenter: UNUserNotificationCenter = .current(),
        managesNotifications: Bool = true
    ) {
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        self.managesNotifications = managesNotifications

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = applicationSupport.appendingPathComponent("Listello", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let newURL = directory.appendingPathComponent("listello.json")
            let previousURL = applicationSupport
                .appendingPathComponent("QuietList", isDirectory: true)
                .appendingPathComponent("quiet-list.json")
            if !FileManager.default.fileExists(atPath: newURL.path), FileManager.default.fileExists(atPath: previousURL.path) {
                try? FileManager.default.copyItem(at: previousURL, to: newURL)
            }
            self.storageURL = newURL
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--listello-reordering-ui-test") {
            seedReorderingUITestData()
        } else {
            load()
        }
        #else
        load()
        #endif
        normalizePreferences()
        normalizeSortIndices()
        normalizeProjectSortIndices()
        applyAutomaticArchiving()
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    var activeTasks: [TaskItem] {
        sortedTasks(
            tasks.filter { task in
                !task.isCompleted
                    && !task.isArchived
                    && (task.hiddenUntil ?? .distantPast) <= Date()
                    && !isHiddenFromAllTasks(task)
            },
            by: preferences.taskSortOption,
            direction: preferences.taskSortDirection
        )
    }

    var completedTasks: [TaskItem] {
        tasks
            .filter { $0.isCompleted && !$0.isArchived && !isHiddenFromAllTasks($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var archivedTasks: [TaskItem] {
        tasks
            .filter(\.isArchived)
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    var orderedProjects: [ProjectItem] {
        projects.sorted { lhs, rhs in
            let left = lhs.sortIndex ?? Int.max
            let right = rhs.sortIndex ?? Int.max
            return left == right ? lhs.createdAt < rhs.createdAt : left < right
        }
    }

    @discardableResult
    func addTask(
        title: String,
        scheduledAt: Date? = nil,
        projectID: UUID? = nil,
        usesDefaultDuration: Bool = true
    ) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let task = TaskItem(
            title: cleanTitle,
            scheduledAt: scheduledAt,
            expectedDurationMinutes: usesDefaultDuration ? preferences.defaultDurationMinutes : nil,
            projectID: validProjectID(projectID),
            sortIndex: nextSortIndex
        )
        tasks.append(task)
        persist()
        return task
    }

    func saveTask(_ task: TaskItem) async {
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var cleanTask = task
        cleanTask.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.projectID = validProjectID(task.projectID)
        if cleanTask.sortIndex == nil { cleanTask.sortIndex = nextSortIndex }
        if cleanTask.scheduledAt == nil {
            cleanTask.notifiesAtScheduledTime = false
            cleanTask.recurrence = .none
            cleanTask.recurrenceExceptions = []
            cleanTask.hiddenUntil = nil
        } else if cleanTask.recurrence == .none {
            cleanTask.recurrenceExceptions = []
            cleanTask.hiddenUntil = nil
        }

        if let index = tasks.firstIndex(where: { $0.id == cleanTask.id }) {
            tasks[index] = cleanTask
        } else {
            tasks.append(cleanTask)
        }

        persist()
        if managesNotifications {
            await rebuildNotifications(requestPermission: cleanTask.notifiesAtScheduledTime)
        }
    }

    func toggleCompleted(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        if task.isRecurring, !tasks[index].isCompleted {
            skipRecurringOccurrence(at: index, occurrenceDate: task.scheduledAt ?? tasks[index].scheduledAt)
            persist()
            rebuildNotificationsSoon()
            return
        }

        tasks[index].completedAt = tasks[index].isCompleted ? nil : Date()
        if tasks[index].isCompleted, preferences.completedArchiveDelayDays == 0 {
            tasks[index].archivedAt = Date()
        }
        if tasks[index].isCompleted {
            tasks[index].calendarEventIdentifier = nil
        }
        persist()
        rebuildNotificationsSoon()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        persist()
        rebuildNotificationsSoon()
    }

    func archiveTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].archivedAt = Date()
        persist()
        rebuildNotificationsSoon()
    }

    @discardableResult
    func archiveAllTasks() -> Int {
        let indices = tasks.indices.filter { !tasks[$0].isArchived }
        guard !indices.isEmpty else { return 0 }
        let now = Date()
        for index in indices { tasks[index].archivedAt = now }
        persist()
        rebuildNotificationsSoon()
        return indices.count
    }

    func restoreArchivedTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].archivedAt = nil
        tasks[index].completedAt = nil
        tasks[index].hiddenUntil = nil
        persist()
        rebuildNotificationsSoon()
    }

    func restoreAllArchivedTasks() {
        guard tasks.contains(where: { $0.isArchived }) else { return }
        for index in tasks.indices where tasks[index].isArchived {
            tasks[index].archivedAt = nil
            tasks[index].completedAt = nil
            tasks[index].hiddenUntil = nil
        }
        persist()
        rebuildNotificationsSoon()
    }

    func deleteAllArchivedTasks() {
        tasks.removeAll { $0.isArchived }
        persist()
        rebuildNotificationsSoon()
    }

    func deleteRecurringOccurrence(_ occurrence: TaskItem) {
        guard
            let index = tasks.firstIndex(where: { $0.id == occurrence.id }),
            tasks[index].isRecurring,
            let occurrenceDate = occurrence.scheduledAt
        else { return }

        skipRecurringOccurrence(at: index, occurrenceDate: occurrenceDate)

        persist()
        rebuildNotificationsSoon()
    }

    func filteredArchivedTasks(query: String) -> [TaskItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return archivedTasks }
        return archivedTasks.filter { task in
            task.title.localizedCaseInsensitiveContains(cleanQuery)
                || task.notes.localizedCaseInsensitiveContains(cleanQuery)
                || project(withID: task.projectID)?.name.localizedCaseInsensitiveContains(cleanQuery) == true
        }
    }

    func filteredTasks(mode: TaskListMode, query: String, projectID: UUID?) -> [TaskItem] {
        let source = tasks.filter { task in
            guard !task.isArchived else { return false }
            if mode == .active {
                return !task.isCompleted && (task.hiddenUntil ?? .distantPast) <= Date()
            }
            return task.isCompleted
        }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = source.filter { task in
            let matchesProject = projectID.map { task.projectID == $0 } ?? !isHiddenFromAllTasks(task)
            let matchesQuery = cleanQuery.isEmpty
                || task.title.localizedCaseInsensitiveContains(cleanQuery)
                || task.notes.localizedCaseInsensitiveContains(cleanQuery)
            return matchesProject && matchesQuery
        }
        return sortedTasks(
            filtered,
            by: preferences.taskSortOption,
            direction: preferences.taskSortDirection
        )
    }

    func tasks(on day: Date) -> [TaskItem] {
        tasks
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap { task in
                guard let occurrence = occurrence(of: task, on: day) else { return nil }
                var scheduledTask = task
                scheduledTask.scheduledAt = occurrence
                if !calendar.isDate(occurrence, equalTo: task.scheduledAt ?? occurrence, toGranularity: .minute) {
                    scheduledTask.calendarEventIdentifier = nil
                }
                return scheduledTask
            }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    func breaks(on day: Date) -> [ScheduleBreakItem] {
        scheduleBreaks
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    func saveBreak(_ scheduleBreak: ScheduleBreakItem) {
        var cleanBreak = scheduleBreak
        cleanBreak.title = scheduleBreak.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBreak.title.isEmpty { cleanBreak.title = L10n.text("Break") }
        cleanBreak.durationMinutes = max(1, min(1_440, cleanBreak.durationMinutes))
        if let index = scheduleBreaks.firstIndex(where: { $0.id == cleanBreak.id }) {
            scheduleBreaks[index] = cleanBreak
        } else {
            scheduleBreaks.append(cleanBreak)
        }
        persist()
    }

    func deleteBreak(_ scheduleBreak: ScheduleBreakItem) {
        scheduleBreaks.removeAll { $0.id == scheduleBreak.id }
        persist()
    }

    func suggestedTask(from visibleTasks: [TaskItem], excluding excludedID: UUID? = nil) -> TaskItem? {
        var candidates = visibleTasks.filter { !$0.isCompleted && $0.id != excludedID }
        if candidates.isEmpty {
            candidates = visibleTasks.filter { !$0.isCompleted }
        }
        guard !candidates.isEmpty else { return nil }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let timely = candidates.filter { ($0.scheduledAt ?? .distantFuture) < endOfToday }
        let important = candidates.filter(\.isImportant)

        if let task = timely.randomElement() { return task }
        if let task = important.randomElement() { return task }
        return candidates.randomElement()
    }

    func project(withID id: UUID?) -> ProjectItem? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func task(withID id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    @discardableResult
    func addProject(
        name: String,
        color: ProjectColor,
        kind: ProjectKind = .project,
        hidesFromAllTasks: Bool? = nil
    ) -> ProjectItem? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let project = ProjectItem(
            name: cleanName,
            color: color,
            kind: kind,
            hidesFromAllTasks: hidesFromAllTasks,
            sortIndex: nextProjectSortIndex
        )
        projects.append(project)
        persist()
        return project
    }

    func saveProject(_ project: ProjectItem) {
        let cleanName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].name = cleanName
        projects[index].color = project.color
        projects[index].kind = project.kind
        projects[index].hidesFromAllTasks = project.hidesFromAllTasks
        persist()
    }

    func deleteProject(_ project: ProjectItem, disposition: ProjectDeletionDisposition) {
        let now = Date()
        projects.removeAll { $0.id == project.id }
        for index in tasks.indices where tasks[index].projectID == project.id {
            tasks[index].projectID = nil
            if disposition == .archiveContents {
                tasks[index].archivedAt = now
            }
        }
        persist()
        rebuildNotificationsSoon()
    }

    @discardableResult
    func importReminders(
        _ reminders: [ImportedReminder],
        into project: ProjectItem,
        skippingExistingTitles: Bool = false
    ) -> Int {
        guard projects.contains(where: { $0.id == project.id }) else { return 0 }
        var importedCount = 0
        var existingTitles = skippingExistingTitles
            ? Set(tasks.lazy.filter { $0.projectID == project.id }.map { self.normalizedTitle($0.title) })
            : []

        for reminder in reminders {
            let cleanTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { continue }
            let titleKey = normalizedTitle(cleanTitle)
            guard !skippingExistingTitles || !existingTitles.contains(titleKey) else { continue }
            tasks.append(TaskItem(
                title: cleanTitle,
                notes: reminder.notes,
                scheduledAt: reminder.dueDate,
                expectedDurationMinutes: project.kind == .list ? nil : preferences.defaultDurationMinutes,
                isImportant: reminder.isImportant,
                projectID: project.id,
                sortIndex: nextSortIndex
            ))
            existingTitles.insert(titleKey)
            importedCount += 1
        }
        persist()
        return importedCount
    }

    func moveTasks(
        _ source: IndexSet,
        to destination: Int,
        within visibleTasks: [TaskItem],
        direction: TaskSortDirection = .ascending
    ) {
        let displayedOrder = moved(visibleTasks, from: source, to: destination)
        let reordered = direction == .ascending ? displayedOrder : Array(displayedOrder.reversed())
        let visibleIDs = Set(visibleTasks.map(\.id))
        var replacements = reordered.makeIterator()
        var allOrdered = tasks.sorted(by: listOrder)
        for index in allOrdered.indices where visibleIDs.contains(allOrdered[index].id) {
            if let replacement = replacements.next() { allOrdered[index] = replacement }
        }
        for (index, task) in allOrdered.enumerated() {
            if let storedIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[storedIndex].sortIndex = index
            }
        }
        persist()
    }

    func moveTask(_ draggedID: UUID, relativeTo targetID: UUID, within visibleTasks: [TaskItem]) {
        guard
            draggedID != targetID,
            let source = visibleTasks.firstIndex(where: { $0.id == draggedID }),
            let target = visibleTasks.firstIndex(where: { $0.id == targetID })
        else { return }
        let destination = source < target ? target + 1 : target
        moveTasks(IndexSet(integer: source), to: destination, within: visibleTasks)
    }

    func moveProjects(_ source: IndexSet, to destination: Int) {
        let reordered = moved(orderedProjects, from: source, to: destination)
        for (index, project) in reordered.enumerated() {
            if let storedIndex = projects.firstIndex(where: { $0.id == project.id }) {
                projects[storedIndex].sortIndex = index
            }
        }
        persist()
    }

    func moveProject(_ draggedID: UUID, relativeTo targetID: UUID) {
        let visibleProjects = orderedProjects
        guard
            draggedID != targetID,
            let source = visibleProjects.firstIndex(where: { $0.id == draggedID }),
            let target = visibleProjects.firstIndex(where: { $0.id == targetID })
        else { return }
        let destination = source < target ? target + 1 : target
        moveProjects(IndexSet(integer: source), to: destination)
    }

    func scheduleConflict(for task: TaskItem, calendarEntries: [CalendarEntry]) -> ScheduleConflict? {
        guard let chosenStart = task.scheduledAt, let durationMinutes = task.expectedDurationMinutes else { return nil }
        return scheduleConflict(
            chosenStart: chosenStart,
            durationMinutes: durationMinutes,
            excludingTaskID: task.id,
            excludingBreakID: nil,
            calendarEventIdentifier: task.calendarEventIdentifier,
            calendarEntries: calendarEntries
        )
    }

    func scheduleConflict(for scheduleBreak: ScheduleBreakItem, calendarEntries: [CalendarEntry]) -> ScheduleConflict? {
        scheduleConflict(
            chosenStart: scheduleBreak.startDate,
            durationMinutes: scheduleBreak.durationMinutes,
            excludingTaskID: nil,
            excludingBreakID: scheduleBreak.id,
            calendarEventIdentifier: nil,
            calendarEntries: calendarEntries
        )
    }

    func saveTaskShiftingFollowing(
        _ task: TaskItem,
        calendarEntries: [CalendarEntry]
    ) async -> [TaskItem] {
        guard
            let chosenStart = task.scheduledAt,
            let durationMinutes = task.expectedDurationMinutes,
            let plan = makeShiftPlan(
                chosenStart: chosenStart,
                durationMinutes: durationMinutes,
                excludingTaskID: task.id,
                excludingBreakID: nil,
                calendarEventIdentifier: task.calendarEventIdentifier,
                calendarEntries: calendarEntries
            )
        else {
            await saveTask(task)
            return []
        }

        let shiftedTasks = applyShiftPlan(plan)
        await saveTask(task)
        return shiftedTasks
    }

    func saveBreakShiftingFollowing(
        _ scheduleBreak: ScheduleBreakItem,
        calendarEntries: [CalendarEntry]
    ) -> [TaskItem] {
        guard let plan = makeShiftPlan(
            chosenStart: scheduleBreak.startDate,
            durationMinutes: scheduleBreak.durationMinutes,
            excludingTaskID: nil,
            excludingBreakID: scheduleBreak.id,
            calendarEventIdentifier: nil,
            calendarEntries: calendarEntries
        ) else {
            saveBreak(scheduleBreak)
            return []
        }

        let shiftedTasks = applyShiftPlan(plan)
        saveBreak(scheduleBreak)
        rebuildNotificationsSoon()
        return shiftedTasks
    }

    private func scheduleConflict(
        chosenStart: Date,
        durationMinutes: Int,
        excludingTaskID: UUID?,
        excludingBreakID: UUID?,
        calendarEventIdentifier: String?,
        calendarEntries: [CalendarEntry]
    ) -> ScheduleConflict? {
        let duration = TimeInterval(max(1, durationMinutes) * 60)
        let chosenEnd = chosenStart.addingTimeInterval(duration)

        var busySlots: [(title: String, start: Date, end: Date)] = tasks(on: chosenStart).compactMap { existingTask in
            guard
                existingTask.id != excludingTaskID,
                let start = existingTask.scheduledAt,
                let existingDuration = existingTask.expectedDurationMinutes
            else { return nil }
            return (existingTask.title, start, start.addingTimeInterval(TimeInterval(existingDuration * 60)))
        }
        busySlots.append(contentsOf: breaks(on: chosenStart).compactMap { existingBreak in
            guard existingBreak.id != excludingBreakID else { return nil }
            return (existingBreak.title, existingBreak.startDate, existingBreak.endDate)
        })
        busySlots.append(contentsOf: calendarEntries.compactMap { entry in
            guard !entry.isAllDay, entry.id != calendarEventIdentifier else { return nil }
            return (entry.title, entry.startDate, entry.endDate)
        })

        guard let firstConflict = busySlots
            .filter({ overlaps(start: chosenStart, end: chosenEnd, otherStart: $0.start, otherEnd: $0.end) })
            .sorted(by: { $0.start < $1.start })
            .first
        else { return nil }

        var candidate = chosenStart
        let sortedSlots = busySlots.sorted { $0.start < $1.start }
        for _ in 0..<100 {
            let candidateEnd = candidate.addingTimeInterval(duration)
            guard let overlap = sortedSlots.first(where: {
                overlaps(start: candidate, end: candidateEnd, otherStart: $0.start, otherEnd: $0.end)
            }) else { break }
            candidate = roundedUpToQuarterHour(overlap.end)
        }

        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: chosenStart) ?? chosenEnd
        if candidate.addingTimeInterval(duration) > endOfDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: chosenStart) ?? chosenStart
            candidate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? nextDay
        }

        let canShiftFollowingEntries = makeShiftPlan(
            chosenStart: chosenStart,
            durationMinutes: durationMinutes,
            excludingTaskID: excludingTaskID,
            excludingBreakID: excludingBreakID,
            calendarEventIdentifier: calendarEventIdentifier,
            calendarEntries: calendarEntries
        ) != nil

        return ScheduleConflict(
            conflictingTitle: firstConflict.title,
            chosenStart: chosenStart,
            suggestedStart: candidate,
            canShiftFollowingEntries: canShiftFollowingEntries
        )
    }

    private func makeShiftPlan(
        chosenStart: Date,
        durationMinutes: Int,
        excludingTaskID: UUID?,
        excludingBreakID: UUID?,
        calendarEventIdentifier: String?,
        calendarEntries: [CalendarEntry]
    ) -> ScheduleShiftPlan? {
        let insertedEnd = chosenStart.addingTimeInterval(TimeInterval(max(1, durationMinutes) * 60))

        let taskSlots = tasks(on: chosenStart).compactMap { task -> ShiftableScheduleSlot? in
            guard
                task.id != excludingTaskID,
                let start = task.scheduledAt,
                let duration = task.expectedDurationMinutes
            else { return nil }
            return ShiftableScheduleSlot(
                item: .task(task),
                start: start,
                end: start.addingTimeInterval(TimeInterval(max(1, duration) * 60))
            )
        }
        let movableCalendarIdentifiers = Set(
            taskSlots.compactMap { slot -> String? in
                guard case .task(let task) = slot.item else { return nil }
                return task.calendarEventIdentifier
            }
        )
        let breakSlots = breaks(on: chosenStart).compactMap { scheduleBreak -> ShiftableScheduleSlot? in
            guard scheduleBreak.id != excludingBreakID else { return nil }
            return ShiftableScheduleSlot(
                item: .scheduleBreak(scheduleBreak),
                start: scheduleBreak.startDate,
                end: scheduleBreak.endDate
            )
        }
        let fixedSlots = calendarEntries.compactMap { entry -> OccupiedScheduleSlot? in
            guard
                !entry.isAllDay,
                entry.id != calendarEventIdentifier,
                !movableCalendarIdentifiers.contains(entry.id)
            else { return nil }
            return OccupiedScheduleSlot(start: entry.startDate, end: entry.endDate)
        }

        guard !fixedSlots.contains(where: {
            overlaps(start: chosenStart, end: insertedEnd, otherStart: $0.start, otherEnd: $0.end)
        }) else { return nil }

        let localSlots = (taskSlots + breakSlots).sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }
        var occupied = fixedSlots + [OccupiedScheduleSlot(start: chosenStart, end: insertedEnd)]
        var ripple = [OccupiedScheduleSlot(start: chosenStart, end: insertedEnd)]
        var plan = ScheduleShiftPlan()
        let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: chosenStart)
        ) ?? insertedEnd

        for slot in localSlots {
            let isAffected = ripple.contains {
                overlaps(start: slot.start, end: slot.end, otherStart: $0.start, otherEnd: $0.end)
            }
            guard isAffected else {
                occupied.append(OccupiedScheduleSlot(start: slot.start, end: slot.end))
                continue
            }

            let duration = slot.end.timeIntervalSince(slot.start)
            guard let newStart = earliestAvailableStart(
                atOrAfter: slot.start,
                duration: duration,
                occupied: occupied,
                noLaterThan: endOfDay
            ) else { return nil }

            let shiftedSlot = OccupiedScheduleSlot(
                start: newStart,
                end: newStart.addingTimeInterval(duration)
            )
            occupied.append(shiftedSlot)
            ripple.append(shiftedSlot)

            switch slot.item {
            case .task(let task):
                plan.taskMoves.append(ScheduledTaskMove(occurrence: task, newStart: newStart))
            case .scheduleBreak(let scheduleBreak):
                plan.breakMoves.append(ScheduledBreakMove(scheduleBreak: scheduleBreak, newStart: newStart))
            }
        }

        return plan.isEmpty ? nil : plan
    }

    private func earliestAvailableStart(
        atOrAfter start: Date,
        duration: TimeInterval,
        occupied: [OccupiedScheduleSlot],
        noLaterThan endOfDay: Date
    ) -> Date? {
        var candidate = start
        for _ in 0..<500 {
            let candidateEnd = candidate.addingTimeInterval(duration)
            if candidateEnd > endOfDay { return nil }
            let overlappingEnds = occupied.compactMap { slot -> Date? in
                overlaps(start: candidate, end: candidateEnd, otherStart: slot.start, otherEnd: slot.end)
                    ? slot.end
                    : nil
            }
            guard let latestEnd = overlappingEnds.max() else { return candidate }
            candidate = latestEnd
        }
        return nil
    }

    private func applyShiftPlan(_ plan: ScheduleShiftPlan) -> [TaskItem] {
        var shiftedTasks: [TaskItem] = []

        for move in plan.taskMoves {
            guard let index = tasks.firstIndex(where: { $0.id == move.occurrence.id }) else { continue }
            if tasks[index].isRecurring, let occurrenceDate = move.occurrence.scheduledAt {
                if !tasks[index].recurrenceExceptions.contains(where: {
                    calendar.isDate($0, inSameDayAs: occurrenceDate)
                }) {
                    tasks[index].recurrenceExceptions.append(occurrenceDate)
                }
                if move.occurrence.calendarEventIdentifier != nil {
                    tasks[index].calendarEventIdentifier = nil
                }

                let shiftedOccurrence = TaskItem(
                    title: move.occurrence.title,
                    notes: move.occurrence.notes,
                    createdAt: move.occurrence.createdAt,
                    scheduledAt: move.newStart,
                    expectedDurationMinutes: move.occurrence.expectedDurationMinutes,
                    notifiesAtScheduledTime: move.occurrence.notifiesAtScheduledTime,
                    isImportant: move.occurrence.isImportant,
                    projectID: move.occurrence.projectID,
                    sortIndex: nextSortIndex,
                    calendarEventIdentifier: move.occurrence.calendarEventIdentifier
                )
                tasks.append(shiftedOccurrence)
                shiftedTasks.append(shiftedOccurrence)
            } else {
                tasks[index].scheduledAt = move.newStart
                shiftedTasks.append(tasks[index])
            }
        }

        for move in plan.breakMoves {
            guard let index = scheduleBreaks.firstIndex(where: { $0.id == move.scheduleBreak.id }) else { continue }
            scheduleBreaks[index].startDate = move.newStart
        }

        return shiftedTasks
    }

    func isDayNotificationsEnabled(_ day: Date) -> Bool {
        notificationDayKeys.contains(dayKey(for: day))
    }

    @discardableResult
    func setDayNotifications(_ enabled: Bool, for day: Date) async -> Bool {
        let key = dayKey(for: day)

        if enabled {
            guard await requestNotificationPermission() else { return false }
            notificationDayKeys.insert(key)
        } else {
            notificationDayKeys.remove(key)
        }

        persist()
        if managesNotifications {
            await rebuildNotifications(requestPermission: false)
        }
        return true
    }

    func suggestedScheduleTime(on day: Date, excluding taskID: UUID? = nil) -> Date {
        let fallback: Date
        if calendar.isDateInToday(day) {
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
            fallback = calendar.date(from: parts) ?? nextHour
        } else {
            fallback = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }

        let mostRecentlyAdded = tasks(on: day)
            .filter { $0.id != taskID }
            .max { $0.createdAt < $1.createdAt }
        guard let mostRecentlyAdded, let start = mostRecentlyAdded.scheduledAt else { return fallback }
        let duration = mostRecentlyAdded.expectedDurationMinutes ?? preferences.defaultDurationMinutes
        let finish = start.addingTimeInterval(TimeInterval(max(1, duration) * 60))
        return max(finish, fallback)
    }

    func setDurationOptions(_ options: [Int]) {
        let cleaned = Array(Set(options.filter { (1...1_440).contains($0) })).sorted()
        guard !cleaned.isEmpty else { return }
        preferences.durationOptions = cleaned
        if !cleaned.contains(preferences.defaultDurationMinutes) {
            preferences.defaultDurationMinutes = cleaned.min(by: {
                abs($0 - preferences.defaultDurationMinutes) < abs($1 - preferences.defaultDurationMinutes)
            }) ?? cleaned[0]
        }
        persist()
    }

    func setDefaultDuration(_ minutes: Int) {
        guard preferences.durationOptions.contains(minutes) else { return }
        preferences.defaultDurationMinutes = minutes
        persist()
    }

    func setCompletedArchiveDelayDays(_ days: Int?) {
        preferences.completedArchiveDelayDays = days
        persist()
        applyAutomaticArchiving()
    }

    func setAppearance(_ appearance: AppearancePreference) {
        preferences.appearance = appearance
        persist()
    }

    func setNotifyNewScheduledTasks(_ enabled: Bool) {
        preferences.notifyNewScheduledTasks = enabled
        persist()
    }

    func setImportantTasksFirst(_ enabled: Bool) {
        preferences.importantTasksFirst = enabled
        persist()
    }

    func setShowNotesInList(_ enabled: Bool) {
        preferences.showNotesInList = enabled
        persist()
    }

    func setTaskSortOption(_ option: TaskSortOption) {
        preferences.taskSortOption = option
        persist()
    }

    func setTaskSortDirection(_ direction: TaskSortDirection) {
        preferences.taskSortDirection = direction
        persist()
    }

    @discardableResult
    func applyAutomaticArchiving(now: Date = Date()) -> Int {
        guard let delayDays = preferences.completedArchiveDelayDays else { return 0 }
        var archivedCount = 0

        for index in tasks.indices {
            guard
                !tasks[index].isArchived,
                let completedAt = tasks[index].completedAt,
                let archiveDate = calendar.date(byAdding: .day, value: delayDays, to: completedAt),
                archiveDate <= now
            else { continue }

            tasks[index].archivedAt = now
            archivedCount += 1
        }

        if archivedCount > 0 {
            persist()
            rebuildNotificationsSoon()
        }
        return archivedCount
    }

    private var nextSortIndex: Int {
        (tasks.compactMap(\.sortIndex).max() ?? -1) + 1
    }

    private var nextProjectSortIndex: Int {
        (projects.compactMap(\.sortIndex).max() ?? -1) + 1
    }

    private func listOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if preferences.importantTasksFirst, lhs.isImportant != rhs.isImportant {
            return lhs.isImportant && !rhs.isImportant
        }
        let leftIndex = lhs.sortIndex ?? Int.max
        let rightIndex = rhs.sortIndex ?? Int.max
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        return lhs.createdAt < rhs.createdAt
    }

    func sortedTasks(
        _ candidates: [TaskItem],
        by option: TaskSortOption,
        direction: TaskSortDirection
    ) -> [TaskItem] {
        candidates.sorted { lhs, rhs in
            if preferences.importantTasksFirst,
               option != .importance,
               lhs.isImportant != rhs.isImportant {
                return lhs.isImportant && !rhs.isImportant
            }

            if let missingValueOrder = missingValueOrder(lhs, rhs, by: option) {
                return missingValueOrder
            }

            let comparison = taskComparison(lhs, rhs, by: option)
            if comparison != .orderedSame {
                return direction == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }

            let leftIndex = lhs.sortIndex ?? Int.max
            let rightIndex = rhs.sortIndex ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func missingValueOrder(
        _ lhs: TaskItem,
        _ rhs: TaskItem,
        by option: TaskSortOption
    ) -> Bool? {
        switch option {
        case .projectOrList:
            return presentValuesFirst(
                project(withID: lhs.projectID)?.name,
                project(withID: rhs.projectID)?.name
            )
        case .scheduledDate:
            return presentValuesFirst(lhs.scheduledAt, rhs.scheduledAt)
        case .duration:
            return presentValuesFirst(lhs.expectedDurationMinutes, rhs.expectedDurationMinutes)
        default:
            return nil
        }
    }

    private func presentValuesFirst<T>(_ lhs: T?, _ rhs: T?) -> Bool? {
        switch (lhs, rhs) {
        case (_?, nil): return true
        case (nil, _?): return false
        default: return nil
        }
    }

    private func taskComparison(
        _ lhs: TaskItem,
        _ rhs: TaskItem,
        by option: TaskSortOption
    ) -> ComparisonResult {
        switch option {
        case .manual:
            return compare(lhs.sortIndex ?? Int.max, rhs.sortIndex ?? Int.max)
        case .dateAdded:
            return compare(lhs.createdAt, rhs.createdAt)
        case .name:
            return lhs.title.localizedStandardCompare(rhs.title)
        case .projectOrList:
            return compareOptionalText(
                project(withID: lhs.projectID)?.name,
                project(withID: rhs.projectID)?.name
            )
        case .scheduledDate:
            return compareOptional(lhs.scheduledAt, rhs.scheduledAt)
        case .duration:
            return compareOptional(lhs.expectedDurationMinutes, rhs.expectedDurationMinutes)
        case .importance:
            return compare(lhs.isImportant ? 1 : 0, rhs.isImportant ? 1 : 0)
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?): return compare(left, right)
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }

    private func compareOptionalText(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?): return left.localizedStandardCompare(right)
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }

    private func validProjectID(_ id: UUID?) -> UUID? {
        guard let id, projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func isHiddenFromAllTasks(_ task: TaskItem) -> Bool {
        guard let projectID = task.projectID else { return false }
        return projects.first(where: { $0.id == projectID })?.hidesFromAllTasks == true
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func moved<Element>(_ values: [Element], from source: IndexSet, to destination: Int) -> [Element] {
        guard !source.isEmpty else { return values }
        let moving = source.map { values[$0] }
        var result = values
        for index in source.sorted(by: >) { result.remove(at: index) }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), result.count)
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }

    private func occurrence(of task: TaskItem, on day: Date) -> Date? {
        guard let scheduledAt = task.scheduledAt else { return nil }
        if task.recurrence == .none {
            return calendar.isDate(scheduledAt, inSameDayAs: day) ? scheduledAt : nil
        }

        let targetDay = calendar.startOfDay(for: day)
        var candidate = scheduledAt
        guard calendar.startOfDay(for: candidate) <= targetDay else { return nil }

        for _ in 0..<10_000 {
            let candidateDay = calendar.startOfDay(for: candidate)
            if candidateDay == targetDay {
                let isExcluded = task.recurrenceExceptions.contains {
                    calendar.isDate($0, inSameDayAs: candidate)
                }
                return isExcluded ? nil : candidate
            }
            guard candidateDay < targetDay,
                  let next = task.recurrence.nextDate(after: candidate, calendar: calendar)
            else { return nil }
            candidate = next
        }
        return nil
    }

    private func advanceRecurringTask(at index: Int, after occurrenceDate: Date?) {
        guard
            let occurrenceDate,
            tasks[index].isRecurring
        else { return }

        var candidate = occurrenceDate
        let now = Date()
        for _ in 0..<10_000 {
            guard let next = tasks[index].recurrence.nextDate(after: candidate, calendar: calendar) else { return }
            candidate = next
            let isExcluded = tasks[index].recurrenceExceptions.contains {
                calendar.isDate($0, inSameDayAs: candidate)
            }
            if candidate > now, !isExcluded {
                tasks[index].scheduledAt = candidate
                tasks[index].completedAt = nil
                tasks[index].hiddenUntil = calendar.startOfDay(for: candidate)
                tasks[index].calendarEventIdentifier = nil
                tasks[index].recurrenceExceptions.removeAll { $0 < calendar.startOfDay(for: candidate) }
                return
            }
        }
    }

    private func skipRecurringOccurrence(at index: Int, occurrenceDate: Date?) {
        guard let occurrenceDate else { return }
        let occurrenceIsCurrent = calendar.startOfDay(for: occurrenceDate) <= calendar.startOfDay(for: Date())
        if let nextScheduled = tasks[index].scheduledAt,
           calendar.isDate(nextScheduled, inSameDayAs: occurrenceDate)
                || (nextScheduled <= occurrenceDate && occurrenceIsCurrent) {
            advanceRecurringTask(at: index, after: occurrenceDate)
        } else if !tasks[index].recurrenceExceptions.contains(where: {
            calendar.isDate($0, inSameDayAs: occurrenceDate)
        }) {
            tasks[index].recurrenceExceptions.append(occurrenceDate)
        }
    }

    private func overlaps(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Bool {
        start < otherEnd && end > otherStart
    }

    private func roundedUpToQuarterHour(_ date: Date) -> Date {
        let interval = TimeInterval(15 * 60)
        return Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / interval) * interval)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: storageURL),
            let state = try? JSONDecoder().decode(ListelloState.self, from: data)
        else { return }

        tasks = state.tasks
        projects = state.projects
        scheduleBreaks = state.scheduleBreaks
        notificationDayKeys = state.notificationDayKeys
        preferences = state.preferences
    }

    #if DEBUG
    private func seedReorderingUITestData() {
        tasks = [
            TaskItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "First task",
                sortIndex: 0
            ),
            TaskItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                title: "Second task",
                sortIndex: 1
            ),
            TaskItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                title: "Third task",
                sortIndex: 2
            )
        ]
        projects = [
            ProjectItem(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                name: "Alpha project",
                color: .teal,
                sortIndex: 0
            ),
            ProjectItem(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                name: "Beta project",
                color: .sky,
                sortIndex: 1
            ),
            ProjectItem(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                name: "Gamma project",
                color: .amber,
                sortIndex: 2
            )
        ]
        scheduleBreaks = []
        notificationDayKeys = []
        preferences = ListelloPreferences()
        persist()
    }
    #endif

    private func normalizePreferences() {
        let cleaned = Array(Set(preferences.durationOptions.filter { (1...1_440).contains($0) })).sorted()
        preferences.durationOptions = cleaned.isEmpty
            ? [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
            : cleaned
        if !preferences.durationOptions.contains(preferences.defaultDurationMinutes) {
            preferences.defaultDurationMinutes = preferences.durationOptions.first ?? 30
        }
    }

    private func normalizeSortIndices() {
        let orderedIDs = tasks
            .sorted { lhs, rhs in
                let left = lhs.sortIndex ?? Int.max
                let right = rhs.sortIndex ?? Int.max
                return left == right ? lhs.createdAt < rhs.createdAt : left < right
            }
            .map(\.id)
        for (index, id) in orderedIDs.enumerated() {
            if let taskIndex = tasks.firstIndex(where: { $0.id == id }) {
                tasks[taskIndex].sortIndex = index
            }
        }
        if !tasks.isEmpty { persist() }
    }

    private func normalizeProjectSortIndices() {
        let orderedIDs = orderedProjects.map(\.id)
        for (index, id) in orderedIDs.enumerated() {
            if let projectIndex = projects.firstIndex(where: { $0.id == id }) {
                projects[projectIndex].sortIndex = index
            }
        }
        if !projects.isEmpty { persist() }
    }

    private func persist() {
        let state = ListelloState(
            tasks: tasks,
            projects: projects,
            scheduleBreaks: scheduleBreaks,
            notificationDayKeys: notificationDayKeys,
            preferences: preferences
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func requestNotificationPermission() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    private func rebuildNotificationsSoon() {
        guard managesNotifications else { return }
        Task { await rebuildNotifications(requestPermission: false) }
    }

    private func rebuildNotifications(requestPermission: Bool) async {
        if requestPermission, !(await requestNotificationPermission()) { return }

        notificationCenter.removeAllPendingNotificationRequests()

        let now = Date()
        let candidates = tasks
            .filter { !$0.isArchived && !$0.isCompleted }
            .flatMap { task in
                upcomingNotificationDates(for: task, after: now, limit: task.isRecurring ? 12 : 1)
                    .map { (task: task, date: $0) }
            }
            .filter { candidate in
                candidate.task.notifiesAtScheduledTime || isDayNotificationsEnabled(candidate.date)
            }
            .sorted { $0.date < $1.date }
            .prefix(60)

        for candidate in candidates {
            let task = candidate.task
            let scheduledAt = candidate.date

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.notes.isEmpty ? L10n.text("Scheduled for now") : task.notes
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let timestamp = Int(scheduledAt.timeIntervalSince1970)
            let request = UNNotificationRequest(
                identifier: "listello-\(task.id.uuidString)-\(timestamp)",
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    private func upcomingNotificationDates(for task: TaskItem, after date: Date, limit: Int) -> [Date] {
        guard var candidate = task.scheduledAt else { return [] }
        var dates: [Date] = []

        for _ in 0..<10_000 {
            if dates.count >= limit { break }
            let isExcluded = task.recurrenceExceptions.contains {
                calendar.isDate($0, inSameDayAs: candidate)
            }
            if candidate > date, !isExcluded { dates.append(candidate) }
            guard task.isRecurring,
                  let next = task.recurrence.nextDate(after: candidate, calendar: calendar)
            else { break }
            candidate = next
        }
        return dates
    }
}
