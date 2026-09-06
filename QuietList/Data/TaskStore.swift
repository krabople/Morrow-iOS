import Combine
import Foundation
import UserNotifications

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
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
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("QuietList", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.storageURL = directory.appendingPathComponent("quiet-list.json")
        }

        load()
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    var activeTasks: [TaskItem] {
        sorted(tasks.filter { !$0.isCompleted })
    }

    var completedTasks: [TaskItem] {
        tasks
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    @discardableResult
    func addTask(title: String, scheduledAt: Date? = nil) -> TaskItem? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let task = TaskItem(title: cleanTitle, scheduledAt: scheduledAt)
        tasks.append(task)
        persist()
        return task
    }

    func saveTask(_ task: TaskItem) async {
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var cleanTask = task
        cleanTask.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        persist()
        if managesNotifications {
            Task { await rebuildNotifications(requestPermission: false) }
        }
    }

    func clearCompleted() {
        tasks.removeAll(\.isCompleted)
        persist()
    }

    func filteredTasks(mode: TaskListMode, query: String) -> [TaskItem] {
        let source = mode == .active ? activeTasks : completedTasks
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return source }

        return source.filter {
            $0.title.localizedCaseInsensitiveContains(cleanQuery)
                || $0.notes.localizedCaseInsensitiveContains(cleanQuery)
        }
    }

    func tasks(on day: Date) -> [TaskItem] {
        activeTasks.filter { task in
            guard let scheduledAt = task.scheduledAt else { return false }
            return calendar.isDate(scheduledAt, inSameDayAs: day)
        }
    }

    func suggestedTask(excluding excludedID: UUID? = nil) -> TaskItem? {
        var candidates = activeTasks.filter { $0.id != excludedID }
        if candidates.isEmpty {
            candidates = activeTasks
        }
        guard !candidates.isEmpty else { return nil }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let timely = candidates.filter { ($0.scheduledAt ?? .distantFuture) < endOfToday }
        let important = candidates.filter(\.isImportant)

        if let task = timely.randomElement() { return task }
        if let task = important.randomElement() { return task }
        return candidates.randomElement()
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

    private func sorted(_ source: [TaskItem]) -> [TaskItem] {
        source.sorted { lhs, rhs in
            if lhs.isImportant != rhs.isImportant { return lhs.isImportant }

            switch (lhs.scheduledAt, rhs.scheduledAt) {
            case let (left?, right?):
                if left != right { return left < right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return lhs.createdAt < rhs.createdAt
        }
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: storageURL),
            let state = try? JSONDecoder().decode(QuietListState.self, from: data)
        else { return }

        tasks = state.tasks
        notificationDayKeys = state.notificationDayKeys
    }

    private func persist() {
        let state = QuietListState(tasks: tasks, notificationDayKeys: notificationDayKeys)
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
            let request = UNNotificationRequest(identifier: "quiet-list-\(task.id.uuidString)", content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }
}
