import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    let createdAt: Date
    var scheduledAt: Date?
    var notifiesAtScheduledTime: Bool
    var isImportant: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        scheduledAt: Date? = nil,
        notifiesAtScheduledTime: Bool = false,
        isImportant: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.notifiesAtScheduledTime = notifiesAtScheduledTime
        self.isImportant = isImportant
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

enum TaskListMode: String, CaseIterable, Identifiable {
    case active = "List"
    case completed = "Done"

    var id: Self { self }
}

struct QuietListState: Codable {
    var tasks: [TaskItem]
    var notificationDayKeys: Set<String>
}
