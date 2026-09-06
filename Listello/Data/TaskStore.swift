import Combine
import Foundation
import UserNotifications

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var projects: [ProjectItem] = []
    @Published private(set) var notificationDayKeys: Set<String> = []

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
        normalizeSortIndices()
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    var activeTasks: [TaskItem] {
        tasks
            .filter { !$0.isCompleted }
            .sorted(by: listOrder)
    }

    var completedTasks: [TaskItem] {
        tasks
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    @discardableResult
    func addTask(title: String, scheduledAt: Date? = nil, projectID: UUID? = nil) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let task = TaskItem(
            title: cleanTitle,
            scheduledAt: scheduledAt,
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
        tasks[index].completedAt = tasks[index].isCompleted ? nil : Date()
        persist()
        rebuildNotificationsSoon()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        persist()
        rebuildNotificationsSoon()
    }

    func clearCompleted() {
        tasks.removeAll { $0.isCompleted }
        persist()
        rebuildNotificationsSoon()
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
        activeTasks
            .filter { task in
                guard let scheduledAt = task.scheduledAt else { return false }
                return calendar.isDate(scheduledAt, inSameDayAs: day)
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

    func moveTasks(from source: IndexSet, to destination: Int, within visibleTasks: [TaskItem]) {
        guard !source.isEmpty else { return }
        var reordered = visibleTasks
        let moving = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = max(0, min(destination - removedBeforeDestination, reordered.count))
        reordered.insert(contentsOf: moving, at: insertionIndex)

        let availableIndices = visibleTasks
            .map { $0.sortIndex ?? 0 }
            .sorted()
        for (task, sortIndex) in zip(reordered, availableIndices) {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].sortIndex = sortIndex
            }
        }
        persist()
    }

    func project(withID id: UUID?) -> ProjectItem? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
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

    @discardableResult
    func importCalendarEntries(_ entries: [CalendarEntry], projectID: UUID? = nil) -> Int {
        var existingIdentifiers = Set(tasks.compactMap(\.calendarEventIdentifier))
        var importedCount = 0

        for entry in entries where !existingIdentifiers.contains(entry.id) {
            let task = TaskItem(
                title: entry.title,
                notes: entry.notes,
                scheduledAt: entry.startDate,
                expectedDurationMinutes: entry.durationMinutes,
                projectID: validProjectID(projectID),
                sortIndex: nextSortIndex + importedCount,
                calendarEventIdentifier: entry.id
            )
            tasks.append(task)
            existingIdentifiers.insert(entry.id)
            importedCount += 1
        }

        if importedCount > 0 { persist() }
        return importedCount
    }

    func scheduleConflict(for task: TaskItem, calendarEntries: [CalendarEntry]) -> ScheduleConflict? {
        guard let chosenStart = task.scheduledAt, let durationMinutes = task.expectedDurationMinutes else { return nil }
        let duration = TimeInterval(max(1, durationMinutes) * 60)
        let chosenEnd = chosenStart.addingTimeInterval(duration)

        var busySlots: [(title: String, start: Date, end: Date)] = activeTasks.compactMap { existingTask in
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

    private var nextSortIndex: Int {
        (tasks.compactMap(\.sortIndex).max() ?? -1) + 1
    }

    private func listOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let leftIndex = lhs.sortIndex ?? Int.max
        let rightIndex = rhs.sortIndex ?? Int.max
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        return lhs.createdAt < rhs.createdAt
    }

    private func validProjectID(_ id: UUID?) -> UUID? {
        guard let id, projects.contains(where: { $0.id == id }) else { return nil }
        return id
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
        let state = ListelloState(tasks: tasks, projects: projects, notificationDayKeys: notificationDayKeys)
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

        for task in activeTasks {
            guard let scheduledAt = task.scheduledAt, scheduledAt > Date() else { continue }
            let shouldNotify = task.notifiesAtScheduledTime || isDayNotificationsEnabled(scheduledAt)
            guard shouldNotify else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.notes.isEmpty ? "Scheduled for now" : task.notes
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "listello-\(task.id.uuidString)", content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }
}
