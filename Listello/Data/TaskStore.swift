import Combine
import Foundation
import UserNotifications

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var projects: [ProjectItem] = []
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

        load()
        normalizePreferences()
        normalizeSortIndices()
        applyAutomaticArchiving()
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    var activeTasks: [TaskItem] {
        tasks
            .filter { task in
                !task.isCompleted
                    && !task.isArchived
                    && (task.hiddenUntil ?? .distantPast) <= Date()
            }
            .sorted(by: listOrder)
    }

    var completedTasks: [TaskItem] {
        tasks
            .filter { $0.isCompleted && !$0.isArchived }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var archivedTasks: [TaskItem] {
        tasks
            .filter(\.isArchived)
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    @discardableResult
    func addTask(title: String, scheduledAt: Date? = nil, projectID: UUID? = nil) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let task = TaskItem(
            title: cleanTitle,
            scheduledAt: scheduledAt,
            expectedDurationMinutes: preferences.defaultDurationMinutes,
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
        let source = mode == .active ? activeTasks : completedTasks
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return source.filter { task in
            let matchesProject = projectID == nil || task.projectID == projectID
            let matchesQuery = cleanQuery.isEmpty
                || task.title.localizedCaseInsensitiveContains(cleanQuery)
                || task.notes.localizedCaseInsensitiveContains(cleanQuery)
            return matchesProject && matchesQuery
        }
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
    func addProject(name: String, color: ProjectColor) -> ProjectItem? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let project = ProjectItem(name: cleanName, color: color)
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
        persist()
    }

    func deleteProject(_ project: ProjectItem) {
        projects.removeAll { $0.id == project.id }
        for index in tasks.indices where tasks[index].projectID == project.id {
            tasks[index].projectID = nil
        }
        persist()
    }

    func scheduleConflict(for task: TaskItem, calendarEntries: [CalendarEntry]) -> ScheduleConflict? {
        guard let chosenStart = task.scheduledAt, let durationMinutes = task.expectedDurationMinutes else { return nil }
        let duration = TimeInterval(max(1, durationMinutes) * 60)
        let chosenEnd = chosenStart.addingTimeInterval(duration)

        var busySlots: [(title: String, start: Date, end: Date)] = tasks(on: chosenStart).compactMap { existingTask in
            guard
                existingTask.id != task.id,
                let start = existingTask.scheduledAt,
                let existingDuration = existingTask.expectedDurationMinutes
            else { return nil }
            return (existingTask.title, start, start.addingTimeInterval(TimeInterval(existingDuration * 60)))
        }
        busySlots.append(contentsOf: calendarEntries.compactMap { entry in
            guard !entry.isAllDay, entry.id != task.calendarEventIdentifier else { return nil }
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

        return ScheduleConflict(
            conflictingTitle: firstConflict.title,
            chosenStart: chosenStart,
            suggestedStart: candidate
        )
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

    func suggestedScheduleTime(on day: Date) -> Date {
        if calendar.isDateInToday(day) {
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
            return calendar.date(from: parts) ?? nextHour
        }

        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
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

    private func listOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if preferences.importantTasksFirst, lhs.isImportant != rhs.isImportant {
            return lhs.isImportant && !rhs.isImportant
        }
        let leftIndex = lhs.sortIndex ?? Int.max
        let rightIndex = rhs.sortIndex ?? Int.max
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        return lhs.createdAt < rhs.createdAt
    }

    private func validProjectID(_ id: UUID?) -> UUID? {
        guard let id, projects.contains(where: { $0.id == id }) else { return nil }
        return id
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
        notificationDayKeys = state.notificationDayKeys
        preferences = state.preferences
    }

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

    private func persist() {
        let state = ListelloState(
            tasks: tasks,
            projects: projects,
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
            content.body = task.notes.isEmpty ? "Scheduled for now" : task.notes
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
