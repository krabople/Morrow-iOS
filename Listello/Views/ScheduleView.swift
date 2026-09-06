import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService

    @AppStorage("showsCalendarEvents") private var showsCalendarEvents = false
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showsCalendar = false
    @State private var permissionDenied = false
    @State private var calendarEntries: [CalendarEntry] = []
    @State private var editingTask: TaskItem?
    @State private var newTask: TaskItem?
    @State private var taskPendingDeletion: TaskItem?

    private var scheduledTasks: [TaskItem] {
        store.tasks(on: selectedDay)
    }

    private var scheduleItems: [ScheduleItem] {
        let tasks = scheduledTasks.map(ScheduleItem.task)
        let events = (showsCalendarEvents ? calendarEntries : []).map(ScheduleItem.calendar)
        return (tasks + events).sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ListelloBackground()

                VStack(spacing: 10) {
                    ListelloHeader(
                        title: dayTitle,
                        subtitle: selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    )
                    .padding(.horizontal)

                    dayNavigator
                        .padding(.horizontal)

                    List {
                        Section {
                            Toggle(isOn: dayNotificationBinding) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Notifications for this day")
                                    Text("Alert me when each scheduled task is due")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.listelloCoral)
                        }

                        Section {
                            ForEach(scheduleItems) { item in
                                switch item {
                                case .task(let task):
                                    scheduledTaskRow(task)
                                case .calendar(let entry):
                                    CalendarEntryRow(entry: entry)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Timetable")
                                Spacer()
                                if showsCalendarEvents {
                                    Label("Calendar shown", systemImage: "calendar")
                                        .font(.caption2)
                                        .foregroundStyle(Color.listelloViolet)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if scheduleItems.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 34))
                                    .foregroundStyle(Color.listelloTeal)
                                Text("No plans for this day")
                                    .font(.headline)
                                Text("Your normal task list still works without a schedule.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 90)
                            .padding(.horizontal, 36)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: calendarOverlayBinding) {
                            Label("Show Calendar Events", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "calendar.circle")
                    }
                    .accessibilityLabel("Calendar options")

                    Button {
                        newTask = TaskItem(
                            title: "",
                            scheduledAt: store.suggestedScheduleTime(on: selectedDay),
                            expectedDurationMinutes: store.preferences.defaultDurationMinutes,
                            notifiesAtScheduledTime: store.preferences.notifyNewScheduledTasks
                        )
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add scheduled task")
                }
            }
            .sheet(isPresented: $showsCalendar) {
                NavigationStack {
                    DatePicker("Choose a day", selection: $selectedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Choose a Day")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCalendar = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(task: task, isNew: false)
            }
            .sheet(item: $newTask) { task in
                TaskEditorView(task: task, isNew: true)
            }
            .alert("Calendar Access Needed", isPresented: $permissionDenied) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Allow full Calendar access for Listello in iPhone Settings to show events.")
            }
            .confirmationDialog(
                "Delete recurring task?",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let task = taskPendingDeletion {
                    Button("Delete This Occurrence", role: .destructive) {
                        deleteOccurrence(task)
                        taskPendingDeletion = nil
                    }
                    Button("Delete All Future Occurrences", role: .destructive) {
                        deleteSeries(task)
                        taskPendingDeletion = nil
                    }
                }
                Button("Cancel", role: .cancel) { taskPendingDeletion = nil }
            } message: {
                Text("Keep the series going, or remove the recurring task completely.")
            }
            .task(id: calendarRefreshKey) {
                await loadCalendarEntries()
            }
        }
    }

    private func scheduledTaskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.scheduledAt?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if let end = taskEnd(task) {
                    Text("to \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Color.listelloInk)
            .frame(width: 72, alignment: .leading)
            .padding(.top, 13)

            TaskRow(
                task: task,
                project: store.project(withID: task.projectID),
                showsScheduleLabel: false
            ) {
                completeTask(task)
            }
        }
        .onTapGesture { editingTask = task }
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                completeTask(task)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.listelloTeal)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                withAnimation { store.archiveTask(task) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.listelloViolet)

            Button(role: .destructive) {
                if task.isRecurring {
                    taskPendingDeletion = task
                } else {
                    deleteTask(task)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button { moveDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            Button {
                showsCalendar = true
            } label: {
                Label("Choose date", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.listelloSky.opacity(0.13), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { moveDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next day")
        }
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "Today" }
        if Calendar.current.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.day().month(.abbreviated))
    }

    private var dayNotificationBinding: Binding<Bool> {
        Binding(
            get: { store.isDayNotificationsEnabled(selectedDay) },
            set: { enabled in
                Task {
                    let succeeded = await store.setDayNotifications(enabled, for: selectedDay)
                    if enabled && !succeeded { permissionDenied = true }
                }
            }
        )
    }

    private var calendarOverlayBinding: Binding<Bool> {
        Binding(
            get: { showsCalendarEvents },
            set: { enabled in
                if enabled {
                    Task {
                        guard await calendarService.requestFullAccess() else {
                            permissionDenied = true
                            return
                        }
                        showsCalendarEvents = true
                        await loadCalendarEntries()
                    }
                } else {
                    showsCalendarEvents = false
                    calendarEntries = []
                }
            }
        )
    }

    private var calendarRefreshKey: String {
        "\(selectedDay.timeIntervalSince1970)-\(showsCalendarEvents)-\(calendarService.authorizationStatus.rawValue)"
    }

    private func taskEnd(_ task: TaskItem) -> Date? {
        guard let start = task.scheduledAt, let minutes = task.expectedDurationMinutes else { return nil }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func moveDay(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: amount, to: selectedDay) else { return }
        withAnimation { selectedDay = next }
    }

    private func loadCalendarEntries() async {
        guard showsCalendarEvents, calendarService.hasFullAccess else {
            calendarEntries = []
            return
        }
        calendarEntries = await calendarService.entries(on: selectedDay, requestAccess: false)
    }

    private func completeTask(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.toggleCompleted(task) }
            await loadCalendarEntries()
        }
    }

    private func deleteTask(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.deleteTask(task) }
            await loadCalendarEntries()
        }
    }

    private func deleteOccurrence(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.deleteRecurringOccurrence(task) }
            await loadCalendarEntries()
        }
    }

    private func deleteSeries(_ task: TaskItem) {
        let storedTask = store.task(withID: task.id) ?? task
        Task {
            _ = await calendarService.deleteEvent(for: storedTask)
            withAnimation { store.deleteTask(task) }
            await loadCalendarEntries()
        }
    }

}

private enum ScheduleItem: Identifiable {
    case task(TaskItem)
    case calendar(CalendarEntry)

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id.uuidString)"
        case .calendar(let entry): "calendar-\(entry.id)-\(entry.startDate.timeIntervalSince1970)"
        }
    }

    var startDate: Date {
        switch self {
        case .task(let task): task.scheduledAt ?? .distantFuture
        case .calendar(let entry): entry.startDate
        }
    }
}

private struct CalendarEntryRow: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isAllDay ? "All day" : entry.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if !entry.isAllDay {
                    Text("to \(entry.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, alignment: .leading)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.listelloInk)
                Label("Calendar · \(entry.calendarTitle)", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: entry.colorHex))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.listelloViolet.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: entry.colorHex))
                    .frame(width: 4)
                    .padding(.vertical, 12)
            }
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}
