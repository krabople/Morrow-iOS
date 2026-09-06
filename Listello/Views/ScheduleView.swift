import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService

    @AppStorage("showsCalendarEvents") private var showsCalendarEvents = false
    @AppStorage("scheduleDisplayMode") private var scheduleDisplayMode = ScheduleDisplayMode.list.rawValue
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showsCalendar = false
    @State private var permissionDenied = false
    @State private var calendarEntries: [CalendarEntry] = []
    @State private var editingTask: TaskItem?
    @State private var newTask: TaskItem?
    @State private var editingBreak: ScheduleBreakItem?
    @State private var newBreak: ScheduleBreakItem?
    @State private var taskPendingDeletion: TaskItem?

    private var scheduledTasks: [TaskItem] {
        store.tasks(on: selectedDay)
    }

    private var scheduleItems: [ScheduleItem] {
        let tasks = scheduledTasks.map(ScheduleItem.task)
        let breaks = store.breaks(on: selectedDay).map(ScheduleItem.scheduleBreak)
        let events = (showsCalendarEvents ? calendarEntries : []).map(ScheduleItem.calendar)
        return (tasks + breaks + events).sorted { $0.startDate < $1.startDate }
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

                    Picker("Schedule view", selection: displayModeBinding) {
                        Label("List view", systemImage: "list.bullet").tag(ScheduleDisplayMode.list)
                        Label("Timeline view", systemImage: "calendar.day.timeline.leading").tag(ScheduleDisplayMode.timeline)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if selectedDisplayMode == .list {
                        timetableList
                    } else {
                        timelineView
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

                    Menu {
                        Button {
                            createScheduledTask()
                        } label: {
                            Label("Add scheduled task", systemImage: "checkmark.circle")
                        }
                        Button {
                            newBreak = ScheduleBreakItem(
                                startDate: store.suggestedScheduleTime(on: selectedDay),
                                durationMinutes: store.preferences.defaultDurationMinutes
                            )
                        } label: {
                            Label("Add break", systemImage: "cup.and.saucer.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add to schedule")
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
            .sheet(item: $editingBreak) { scheduleBreak in
                BreakEditorView(scheduleBreak: scheduleBreak, isNew: false)
            }
            .sheet(item: $newBreak) { scheduleBreak in
                BreakEditorView(scheduleBreak: scheduleBreak, isNew: true)
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

    private var timetableList: some View {
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
                                case .scheduleBreak(let scheduleBreak):
                                    breakRow(scheduleBreak)
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

    private var timelineView: some View {
        VStack(spacing: 8) {
            Toggle(isOn: dayNotificationBinding) {
                Label("Notifications for this day", systemImage: "bell")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.listelloCoral)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal)

            ScheduleTimelineView(
                day: selectedDay,
                items: scheduleItems,
                onTaskTap: { editingTask = $0 },
                onBreakTap: { editingBreak = $0 }
            )
        }
    }

    private var selectedDisplayMode: ScheduleDisplayMode {
        ScheduleDisplayMode(rawValue: scheduleDisplayMode) ?? .list
    }

    private var displayModeBinding: Binding<ScheduleDisplayMode> {
        Binding(get: { selectedDisplayMode }, set: { scheduleDisplayMode = $0.rawValue })
    }

    private func createScheduledTask() {
        newTask = TaskItem(
            title: "",
            scheduledAt: store.suggestedScheduleTime(on: selectedDay),
            expectedDurationMinutes: store.preferences.defaultDurationMinutes,
            notifiesAtScheduledTime: store.preferences.notifyNewScheduledTasks
        )
    }

    private func breakRow(_ scheduleBreak: ScheduleBreakItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleBreak.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                Text(L10n.format("to_time", scheduleBreak.endDate.formatted(date: .omitted, time: .shortened)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)
            .padding(.top, 12)

            Label(scheduleBreak.title, systemImage: "cup.and.saucer.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.listelloInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Color.listelloAmber.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        }
        .contentShape(Rectangle())
        .onTapGesture { editingBreak = scheduleBreak }
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteBreak(scheduleBreak) }
            }
        }
    }

    private func scheduledTaskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.scheduledAt?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if let end = taskEnd(task) {
                    Text(L10n.format("to_time", end.formatted(date: .omitted, time: .shortened)))
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
        if Calendar.current.isDateInToday(selectedDay) { return L10n.text("Today") }
        if Calendar.current.isDateInTomorrow(selectedDay) { return L10n.text("Tomorrow") }
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

private enum ScheduleDisplayMode: String {
    case list
    case timeline
}

private enum ScheduleItem: Identifiable {
    case task(TaskItem)
    case calendar(CalendarEntry)
    case scheduleBreak(ScheduleBreakItem)

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id.uuidString)"
        case .calendar(let entry): "calendar-\(entry.id)-\(entry.startDate.timeIntervalSince1970)"
        case .scheduleBreak(let scheduleBreak): "break-\(scheduleBreak.id.uuidString)"
        }
    }

    var startDate: Date {
        switch self {
        case .task(let task): task.scheduledAt ?? .distantFuture
        case .calendar(let entry): entry.startDate
        case .scheduleBreak(let scheduleBreak): scheduleBreak.startDate
        }
    }

    var endDate: Date {
        switch self {
        case .task(let task):
            return startDate.addingTimeInterval(TimeInterval(task.effectiveDurationMinutes * 60))
        case .calendar(let entry): return entry.endDate
        case .scheduleBreak(let scheduleBreak): return scheduleBreak.endDate
        }
    }

    var isAllDay: Bool {
        if case .calendar(let entry) = self { return entry.isAllDay }
        return false
    }
}

private struct ScheduleTimelineView: View {
    @EnvironmentObject private var store: TaskStore

    let day: Date
    let items: [ScheduleItem]
    let onTaskTap: (TaskItem) -> Void
    let onBreakTap: (ScheduleBreakItem) -> Void

    private let hourHeight: CGFloat = 66
    private let timeColumnWidth: CGFloat = 58
    private let laneGap: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !allDayItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("All day", systemImage: "sun.max.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(allDayItems) { item in
                            timelineBlock(item, compact: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            hourGrid(width: geometry.size.width)

                            ForEach(placements) { placement in
                                let availableWidth = max(120, geometry.size.width - timeColumnWidth - 12)
                                let blockWidth = (availableWidth - laneGap * CGFloat(placement.laneCount - 1))
                                    / CGFloat(placement.laneCount)
                                timelineBlock(placement.item, compact: false)
                                    .frame(
                                        width: blockWidth,
                                        height: max(12, CGFloat(placement.durationMinutes) / 60 * hourHeight),
                                        alignment: .topLeading
                                    )
                                    .offset(
                                        x: timeColumnWidth + 6 + CGFloat(placement.lane) * (blockWidth + laneGap),
                                        y: CGFloat(placement.startMinute) / 60 * hourHeight + 2
                                    )
                                    .onTapGesture { open(placement.item) }
                            }

                            if Calendar.current.isDateInToday(day) {
                                currentTimeLine(width: geometry.size.width)
                            }
                        }
                        .frame(width: geometry.size.width, height: hourHeight * 24 + 1, alignment: .topLeading)
                    }
                    .onAppear {
                        proxy.scrollTo("hour-\(initialHour)", anchor: .top)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal)
    }

    private var allDayItems: [ScheduleItem] {
        items.filter(\.isAllDay)
    }

    private var timedItems: [ScheduleItem] {
        items.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
    }

    private var placements: [TimelinePlacement] {
        let calendar = Calendar.current
        var result: [TimelinePlacement] = []
        var cluster: [ScheduleItem] = []
        var clusterEnd: Date?

        func appendCluster(_ values: [ScheduleItem], to output: inout [TimelinePlacement]) {
            guard !values.isEmpty else { return }
            var laneEnds: [Date] = []
            var temporary: [(ScheduleItem, Int)] = []
            for item in values {
                let lane = laneEnds.firstIndex(where: { $0 <= item.startDate }) ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(item.endDate) } else { laneEnds[lane] = item.endDate }
                temporary.append((item, lane))
            }
            let laneCount = max(1, laneEnds.count)
            for (item, lane) in temporary {
                let components = calendar.dateComponents([.hour, .minute], from: item.startDate)
                let startMinute = max(0, min(1_439, (components.hour ?? 0) * 60 + (components.minute ?? 0)))
                let endMinute = max(startMinute + 1, min(1_440, startMinute + Int(item.endDate.timeIntervalSince(item.startDate) / 60)))
                output.append(TimelinePlacement(
                    item: item,
                    lane: lane,
                    laneCount: laneCount,
                    startMinute: startMinute,
                    durationMinutes: endMinute - startMinute
                ))
            }
        }

        for item in timedItems {
            if let currentClusterEnd = clusterEnd, item.startDate >= currentClusterEnd {
                appendCluster(cluster, to: &result)
                cluster = []
                clusterEnd = item.endDate
            } else if clusterEnd == nil {
                clusterEnd = item.endDate
            } else if let currentEnd = clusterEnd, item.endDate > currentEnd {
                clusterEnd = item.endDate
            }
            cluster.append(item)
        }
        appendCluster(cluster, to: &result)
        return result
    }

    private var initialHour: Int {
        if Calendar.current.isDateInToday(day) {
            return max(0, Calendar.current.component(.hour, from: Date()) - 1)
        }
        return max(0, (timedItems.first.map { Calendar.current.component(.hour, from: $0.startDate) } ?? 9) - 1)
    }

    @ViewBuilder
    private func hourGrid(width: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            HStack(spacing: 6) {
                Text(hourLabel(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth - 8, alignment: .trailing)
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: max(1, width - timeColumnWidth), height: 1)
            }
            .frame(height: 1)
            .offset(y: CGFloat(hour) * hourHeight)
            .id("hour-\(hour)")
        }
    }

    private func currentTimeLine(width: CGFloat) -> some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .frame(width: max(1, width - timeColumnWidth))
        .offset(x: timeColumnWidth - 1, y: CGFloat(minutes) / 60 * hourHeight)
    }

    private func timelineBlock(_ item: ScheduleItem, compact: Bool) -> some View {
        let color = color(for: item)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon(for: item))
                Text(title(for: item))
                    .lineLimit(compact ? 1 : 2)
            }
            .font(.caption.weight(.semibold))
            if !compact {
                Text(timeRange(for: item))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.listelloInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(color.opacity(0.24), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func title(for item: ScheduleItem) -> String {
        switch item {
        case .task(let task): task.title
        case .calendar(let entry): entry.title
        case .scheduleBreak(let scheduleBreak): scheduleBreak.title
        }
    }

    private func icon(for item: ScheduleItem) -> String {
        switch item {
        case .task: "checkmark.circle"
        case .calendar: "calendar"
        case .scheduleBreak: "cup.and.saucer.fill"
        }
    }

    private func color(for item: ScheduleItem) -> Color {
        switch item {
        case .task(let task):
            return store.project(withID: task.projectID)?.color.tint ?? (task.isImportant ? .listelloAmber : .listelloTeal)
        case .calendar(let entry): return Color(hex: entry.colorHex)
        case .scheduleBreak: return .listelloAmber
        }
    }

    private func timeRange(for item: ScheduleItem) -> String {
        "\(item.startDate.formatted(date: .omitted, time: .shortened))–\(item.endDate.formatted(date: .omitted, time: .shortened))"
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func open(_ item: ScheduleItem) {
        switch item {
        case .task(let task): onTaskTap(task)
        case .scheduleBreak(let scheduleBreak): onBreakTap(scheduleBreak)
        case .calendar: break
        }
    }
}

private struct TimelinePlacement: Identifiable {
    let item: ScheduleItem
    let lane: Int
    let laneCount: Int
    let startMinute: Int
    let durationMinutes: Int
    var id: String { item.id }
}

private struct CalendarEntryRow: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isAllDay ? L10n.text("All day") : entry.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if !entry.isAllDay {
                    Text(L10n.format("to_time", entry.endDate.formatted(date: .omitted, time: .shortened)))
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
                Label(calendarSourceLabel, systemImage: "calendar")
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

    private var calendarSourceLabel: String {
        entry.calendarTitle
    }
}
