import Combine
import EventKit
import UIKit

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let eventStore = EKEventStore()

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    @discardableResult
    func requestFullAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted { eventStore.reset() }
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func entries(on day: Date, requestAccess: Bool) async -> [CalendarEntry] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return await entries(from: start, to: end, requestAccess: requestAccess)
    }

    func entries(from start: Date, to end: Date, requestAccess: Bool) async -> [CalendarEntry] {
        if !hasFullAccess {
            guard requestAccess, await requestFullAccess() else { return [] }
        }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .map { event in
                CalendarEntry(
                    id: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Calendar event",
                    notes: event.notes ?? "",
                    startDate: event.startDate,
                    endDate: max(event.endDate, event.startDate.addingTimeInterval(60)),
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title,
                    colorHex: Self.hexColor(event.calendar.cgColor)
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func export(_ task: TaskItem) async -> String? {
        guard let startDate = task.scheduledAt else { return nil }
        if !hasFullAccess {
            guard await requestFullAccess() else { return nil }
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = task.title
        event.notes = task.notes.isEmpty ? "Added from Listello" : "\(task.notes)\n\nAdded from Listello"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(task.effectiveDurationMinutes * 60))

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    private static func hexColor(_ cgColor: CGColor) -> String {
        let color = UIColor(cgColor: cgColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#38BDB2" }
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255), Int(green * 255), Int(blue * 255)
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
