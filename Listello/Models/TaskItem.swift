import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    let createdAt: Date
    var scheduledAt: Date?
    var expectedDurationMinutes: Int?
    var notifiesAtScheduledTime: Bool
    var isImportant: Bool
    var completedAt: Date?
    var projectID: UUID?
    var sortIndex: Int?
    var calendarEventIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        scheduledAt: Date? = nil,
        expectedDurationMinutes: Int? = 30,
        notifiesAtScheduledTime: Bool = false,
        isImportant: Bool = false,
        completedAt: Date? = nil,
        projectID: UUID? = nil,
        sortIndex: Int? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.expectedDurationMinutes = expectedDurationMinutes
        self.notifiesAtScheduledTime = notifiesAtScheduledTime
        self.isImportant = isImportant
        self.completedAt = completedAt
        self.projectID = projectID
        self.sortIndex = sortIndex
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var isCompleted: Bool { completedAt != nil }
    var effectiveDurationMinutes: Int { expectedDurationMinutes ?? 30 }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, createdAt, scheduledAt, expectedDurationMinutes
        case notifiesAtScheduledTime, isImportant, completedAt, projectID, sortIndex
        case calendarEventIdentifier
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        scheduledAt = try values.decodeIfPresent(Date.self, forKey: .scheduledAt)
        if values.contains(.expectedDurationMinutes) {
            expectedDurationMinutes = try values.decodeIfPresent(Int.self, forKey: .expectedDurationMinutes)
        } else {
            expectedDurationMinutes = 30
        }
        notifiesAtScheduledTime = try values.decodeIfPresent(Bool.self, forKey: .notifiesAtScheduledTime) ?? false
        isImportant = try values.decodeIfPresent(Bool.self, forKey: .isImportant) ?? false
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        projectID = try values.decodeIfPresent(UUID.self, forKey: .projectID)
        sortIndex = try values.decodeIfPresent(Int.self, forKey: .sortIndex)
        calendarEventIdentifier = try values.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(notes, forKey: .notes)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        if let expectedDurationMinutes {
            try values.encode(expectedDurationMinutes, forKey: .expectedDurationMinutes)
        } else {
            try values.encodeNil(forKey: .expectedDurationMinutes)
        }
        try values.encode(notifiesAtScheduledTime, forKey: .notifiesAtScheduledTime)
        try values.encode(isImportant, forKey: .isImportant)
        try values.encodeIfPresent(completedAt, forKey: .completedAt)
        try values.encodeIfPresent(projectID, forKey: .projectID)
        try values.encodeIfPresent(sortIndex, forKey: .sortIndex)
        try values.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
    }
}

struct ProjectItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var color: ProjectColor
    let createdAt: Date

    init(id: UUID = UUID(), name: String, color: ProjectColor, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }
}

enum ProjectColor: String, CaseIterable, Codable, Identifiable {
    case teal, sky, amber, coral, violet, rose

    var id: Self { self }
}

enum TaskListMode: String, CaseIterable, Identifiable {
    case active = "List"
    case completed = "Done"

    var id: Self { self }
}

struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let colorHex: String

    var durationMinutes: Int {
        max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }
}

struct ScheduleConflict: Identifiable, Equatable {
    let id = UUID()
    let conflictingTitle: String
    let chosenStart: Date
    let suggestedStart: Date
}

struct ListelloState: Codable {
    var tasks: [TaskItem]
    var projects: [ProjectItem]
    var notificationDayKeys: Set<String>

    private enum CodingKeys: String, CodingKey {
        case tasks, projects, notificationDayKeys
    }

    init(tasks: [TaskItem], projects: [ProjectItem], notificationDayKeys: Set<String>) {
        self.tasks = tasks
        self.projects = projects
        self.notificationDayKeys = notificationDayKeys
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try values.decodeIfPresent([ProjectItem].self, forKey: .projects) ?? []
        notificationDayKeys = try values.decodeIfPresent(Set<String>.self, forKey: .notificationDayKeys) ?? []
    }
}
