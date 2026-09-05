import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case today, inbox, plan, focus, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .plan: "Plan"
        case .focus: "Focus"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sparkles"
        case .inbox: "tray"
        case .plan: "calendar"
        case .focus: "scope"
        case .more: "ellipsis.circle"
        }
    }
}

enum EnergyLevel: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
    var rank: Int { self == .low ? 1 : self == .medium ? 2 : 3 }
    var symbol: String { self == .low ? "leaf" : self == .medium ? "bolt" : "brain.head.profile" }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case urgent = 1
    case important = 2
    case normal = 3
    case low = 4

    var id: Int { rawValue }
    var title: String { "P\(rawValue)" }
}

struct Subtask: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var isComplete = false
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes = ""
    var dueDate: Date?
    var durationMinutes = 30
    var project = "Inbox"
    var priority: TaskPriority = .normal
    var energy: EnergyLevel = .medium
    var isComplete = false
    var isFlagged = false
    var isWaiting = false
    var location: String?
    var tags: [String] = []
    var subtasks: [Subtask] = []
    var createdAt = Date()

    var dueText: String {
        guard let dueDate else { return "Anytime" }
        if Calendar.current.isDateInToday(dueDate) {
            return dueDate.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct HabitItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var target: Int
    var progress: Int
    var unit: String
    var streak: Int

    var isComplete: Bool { progress >= target }
}

struct SavedState: Codable {
    var tasks: [TaskItem]
    var habits: [HabitItem]
}

