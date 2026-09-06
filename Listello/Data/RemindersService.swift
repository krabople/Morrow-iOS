import Combine
import CoreGraphics
import EventKit
import Foundation

struct ReminderSourceList: Identifiable, Equatable {
    let id: String
    let title: String
    let colorHex: String
}

@MainActor
final class RemindersService: ObservableObject {
    private let eventStore = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    var hasFullAccess: Bool { authorizationStatus == .fullAccess }

    func requestFullAccess() async -> Bool {
        if hasFullAccess { return true }
        guard authorizationStatus == .notDetermined else { return false }
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func sourceLists() -> [ReminderSourceList] {
        guard hasFullAccess else { return [] }
        return eventStore.calendars(for: .reminder)
            .map {
                ReminderSourceList(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: Self.hexColor($0.cgColor)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func incompleteReminders(in sourceListID: String) async -> [ImportedReminder] {
        guard
            hasFullAccess,
            let sourceList = eventStore.calendar(withIdentifier: sourceListID)
        else { return [] }

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: [sourceList]
        )

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let imported = (reminders ?? []).map { reminder in
                    ImportedReminder(
                        title: reminder.title,
                        notes: reminder.notes ?? "",
                        dueDate: Self.date(from: reminder.dueDateComponents),
                        isImportant: (1...4).contains(reminder.priority)
                    )
                }
                continuation.resume(returning: imported)
            }
        }
    }

    private static func date(from components: DateComponents?) -> Date? {
        guard var components else { return nil }
        if components.calendar == nil { components.calendar = .current }
        if components.timeZone == nil { components.timeZone = .current }
        return components.date
    }

    private static func hexColor(_ color: CGColor?) -> String {
        guard let components = color?.components else { return "38BDB2" }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
        } else {
            red = components[0]
            green = components[0]
            blue = components[0]
        }
        return String(
            format: "%02X%02X%02X",
            Int(red * 255), Int(green * 255), Int(blue * 255)
        )
    }
}
