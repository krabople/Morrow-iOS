import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var tasks: [TaskItem]
    var habits: [HabitItem]
    var selectedTab: AppTab = .today
    var selectedFocusTaskID: UUID?
    var didLoad = false

    init() {
        tasks = Self.sampleTasks()
        habits = Self.sampleHabits()
        load()
    }

    var todayTasks: [TaskItem] {
        tasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var inboxTasks: [TaskItem] {
        tasks.sorted { $0.createdAt > $1.createdAt }
    }

    var openTasks: [TaskItem] { tasks.filter { !$0.isComplete } }
    var focusTask: TaskItem? {
        if let selectedFocusTaskID, let task = task(id: selectedFocusTaskID), !task.isComplete { return task }
        return openTasks.first
    }
    var completedTodayCount: Int { todayTasks.filter(\.isComplete).count }
    var todayMinutes: Int { todayTasks.filter { !$0.isComplete }.reduce(0) { $0 + $1.durationMinutes } }

    func task(id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    func add(_ task: TaskItem) {
        tasks.append(task)
        save()
    }

    func quickAdd(_ text: String) {
        let cleanTitle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let lower = cleanTitle.lowercased()
        let calendar = Calendar.current
        var dueDate: Date?
        if lower.contains("tomorrow") {
            dueDate = calendar.date(byAdding: .day, value: 1, to: Date())
        } else if lower.contains("today") {
            dueDate = Date()
        }
        add(TaskItem(title: cleanTitle, dueDate: dueDate, durationMinutes: 15))
    }

    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isComplete.toggle()
        save()
    }

    func toggleFlag(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isFlagged.toggle()
        save()
    }

    func update(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        save()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func pickTask(maxMinutes: Int, energy: EnergyLevel) -> TaskItem? {
        let matching = openTasks.filter { $0.durationMinutes <= maxMinutes && $0.energy.rank <= energy.rank }
        return (matching.isEmpty ? openTasks : matching).randomElement()
    }

    func startFocus(_ task: TaskItem) {
        selectedFocusTaskID = task.id
        selectedTab = .focus
    }

    func chooseNextFocusTask() {
        let candidates = openTasks
        guard !candidates.isEmpty else { selectedFocusTaskID = nil; return }
        guard let selectedFocusTaskID, let currentIndex = candidates.firstIndex(where: { $0.id == selectedFocusTaskID }) else {
            self.selectedFocusTaskID = candidates[0].id
            return
        }
        self.selectedFocusTaskID = candidates[(currentIndex + 1) % candidates.count].id
    }

    func autoSchedule(on day: Date) {
        let calendar = Calendar.current
        var cursor = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let selectedIDs = tasks.filter { task in
            guard !task.isComplete, let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: day)
        }.map(\.id)
        let idsToSchedule = selectedIDs.isEmpty
            ? Array(tasks.filter { !$0.isComplete && $0.dueDate == nil }.prefix(5).map(\.id))
            : selectedIDs

        for id in idsToSchedule {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
            tasks[index].dueDate = cursor
            cursor = calendar.date(byAdding: .minute, value: tasks[index].durationMinutes + 15, to: cursor) ?? cursor
        }
        save()
    }

    func incrementHabit(_ id: UUID) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].progress = min(habits[index].target, habits[index].progress + 1)
        save()
    }

    private var storeURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Morrow", directoryHint: .isDirectory)
            .appending(path: "state.json")
    }

    private func load() {
        defer { didLoad = true }
        guard let storeURL, let data = try? Data(contentsOf: storeURL), let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        tasks = state.tasks
        habits = state.habits
    }

    private func save() {
        guard didLoad, let storeURL else { return }
        do {
            let folder = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedState(tasks: tasks, habits: habits))
            try data.write(to: storeURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save Morrow state: \(error.localizedDescription)")
        }
    }

    private static func date(hour: Int, dayOffset: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private static func sampleTasks() -> [TaskItem] {
        [
            TaskItem(title: "Shape the launch story", notes: "Turn the research into one clear narrative. Keep the opening concrete and human.", dueDate: date(hour: 9), durationMinutes: 45, project: "Northstar", priority: .urgent, energy: .high, isFlagged: true, tags: ["deep-work"], subtasks: [Subtask(title: "Choose the core message", isComplete: true), Subtask(title: "Draft the three story beats"), Subtask(title: "Add customer proof")]),
            TaskItem(title: "Book annual eye test", notes: "Ask for the earliest Saturday appointment.", dueDate: date(hour: 11), durationMinutes: 10, project: "Personal", priority: .important, energy: .low, location: "High Street", tags: ["errand"]),
            TaskItem(title: "Reply to Mara about Friday", dueDate: date(hour: 14), durationMinutes: 5, project: "People", priority: .important, energy: .low, tags: ["reply"]),
            TaskItem(title: "Walk after dinner", dueDate: date(hour: 19), durationMinutes: 25, project: "Wellbeing", priority: .normal, energy: .low, location: "Home"),
            TaskItem(title: "Review household subscriptions", dueDate: date(hour: 10, dayOffset: 1), durationMinutes: 30, project: "Personal", priority: .normal, energy: .medium),
            TaskItem(title: "Sketch Q4 roadmap", dueDate: date(hour: 9, dayOffset: 2), durationMinutes: 60, project: "Northstar", priority: .urgent, energy: .high, isFlagged: true),
            TaskItem(title: "Send photos to Mum", durationMinutes: 10, project: "People", priority: .low, energy: .low),
            TaskItem(title: "Renew travel insurance", dueDate: date(hour: 12, dayOffset: 7), durationMinutes: 20, project: "Admin", priority: .urgent, energy: .medium, isFlagged: true),
            TaskItem(title: "Try the new lentil recipe", dueDate: date(hour: 18, dayOffset: 4), durationMinutes: 45, project: "Personal", priority: .low, energy: .medium),
        ]
    }

    private static func sampleHabits() -> [HabitItem] {
        [
            HabitItem(title: "Water", symbol: "drop.fill", target: 8, progress: 6, unit: "glasses", streak: 12),
            HabitItem(title: "Stretch", symbol: "figure.cooldown", target: 1, progress: 1, unit: "session", streak: 8),
            HabitItem(title: "Read", symbol: "book.fill", target: 20, progress: 12, unit: "minutes", streak: 21),
            HabitItem(title: "Walk", symbol: "figure.walk", target: 1, progress: 0, unit: "walk", streak: 5),
        ]
    }
}
