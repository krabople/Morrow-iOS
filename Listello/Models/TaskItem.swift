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
    var archivedAt: Date?
    var projectID: UUID?
    var sortIndex: Int?
    var calendarEventIdentifier: String?
    var recurrence: RecurrenceRule
    var recurrenceExceptions: [Date]
    var hiddenUntil: Date?

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
        archivedAt: Date? = nil,
        projectID: UUID? = nil,
        sortIndex: Int? = nil,
        calendarEventIdentifier: String? = nil,
        recurrence: RecurrenceRule = .none,
        recurrenceExceptions: [Date] = [],
        hiddenUntil: Date? = nil
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
        self.archivedAt = archivedAt
        self.projectID = projectID
        self.sortIndex = sortIndex
        self.calendarEventIdentifier = calendarEventIdentifier
        self.recurrence = recurrence
        self.recurrenceExceptions = recurrenceExceptions
        self.hiddenUntil = hiddenUntil
    }

    var isCompleted: Bool { completedAt != nil }
    var isArchived: Bool { archivedAt != nil }
    var isRecurring: Bool { recurrence != .none }
    var effectiveDurationMinutes: Int { expectedDurationMinutes ?? 30 }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, createdAt, scheduledAt, expectedDurationMinutes
        case notifiesAtScheduledTime, isImportant, completedAt, archivedAt, projectID, sortIndex
        case calendarEventIdentifier, recurrence, recurrenceExceptions, hiddenUntil
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
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        projectID = try values.decodeIfPresent(UUID.self, forKey: .projectID)
        sortIndex = try values.decodeIfPresent(Int.self, forKey: .sortIndex)
        calendarEventIdentifier = try values.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        recurrence = try values.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence) ?? .none
        recurrenceExceptions = try values.decodeIfPresent([Date].self, forKey: .recurrenceExceptions) ?? []
        hiddenUntil = try values.decodeIfPresent(Date.self, forKey: .hiddenUntil)
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
        try values.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try values.encodeIfPresent(projectID, forKey: .projectID)
        try values.encodeIfPresent(sortIndex, forKey: .sortIndex)
        try values.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try values.encode(recurrence, forKey: .recurrence)
        try values.encode(recurrenceExceptions, forKey: .recurrenceExceptions)
        try values.encodeIfPresent(hiddenUntil, forKey: .hiddenUntil)
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

enum RecurrenceRule: String, CaseIterable, Codable, Identifiable {
    case none
    case daily
    case weekdays
    case weekly
    case fortnightly
    case monthly
    case yearly

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .fortnightly: "Every fortnight"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    func nextDate(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = date
            for _ in 0..<7 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
                let weekday = calendar.component(.weekday, from: candidate)
                if (2...6).contains(weekday) { return candidate }
            }
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .fortnightly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum AppearancePreference: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct ListelloPreferences: Codable, Equatable {
    var durationOptions: [Int]
    var defaultDurationMinutes: Int
    var completedArchiveDelayDays: Int?
    var appearance: AppearancePreference
    var notifyNewScheduledTasks: Bool
    var importantTasksFirst: Bool
    var showNotesInList: Bool

    init(
        durationOptions: [Int] = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240],
        defaultDurationMinutes: Int = 30,
        completedArchiveDelayDays: Int? = nil,
        appearance: AppearancePreference = .system,
        notifyNewScheduledTasks: Bool = false,
        importantTasksFirst: Bool = false,
        showNotesInList: Bool = true
    ) {
        self.durationOptions = durationOptions
        self.defaultDurationMinutes = defaultDurationMinutes
        self.completedArchiveDelayDays = completedArchiveDelayDays
        self.appearance = appearance
        self.notifyNewScheduledTasks = notifyNewScheduledTasks
        self.importantTasksFirst = importantTasksFirst
        self.showNotesInList = showNotesInList
    }

    private enum CodingKeys: String, CodingKey {
        case durationOptions, defaultDurationMinutes, completedArchiveDelayDays
        case appearance, notifyNewScheduledTasks, importantTasksFirst, showNotesInList
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        durationOptions = try values.decodeIfPresent([Int].self, forKey: .durationOptions)
            ?? [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
        defaultDurationMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultDurationMinutes) ?? 30
        completedArchiveDelayDays = try values.decodeIfPresent(Int.self, forKey: .completedArchiveDelayDays)
        appearance = try values.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? .system
        notifyNewScheduledTasks = try values.decodeIfPresent(Bool.self, forKey: .notifyNewScheduledTasks) ?? false
        importantTasksFirst = try values.decodeIfPresent(Bool.self, forKey: .importantTasksFirst) ?? false
        showNotesInList = try values.decodeIfPresent(Bool.self, forKey: .showNotesInList) ?? true
    }
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
    var preferences: ListelloPreferences

    private enum CodingKeys: String, CodingKey {
        case tasks, projects, notificationDayKeys, preferences
    }

    init(
        tasks: [TaskItem],
        projects: [ProjectItem],
        notificationDayKeys: Set<String>,
        preferences: ListelloPreferences = ListelloPreferences()
    ) {
        self.tasks = tasks
        self.projects = projects
        self.notificationDayKeys = notificationDayKeys
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try values.decodeIfPresent([ProjectItem].self, forKey: .projects) ?? []
        notificationDayKeys = try values.decodeIfPresent(Set<String>.self, forKey: .notificationDayKeys) ?? []
        preferences = try values.decodeIfPresent(ListelloPreferences.self, forKey: .preferences) ?? ListelloPreferences()
    }
}
