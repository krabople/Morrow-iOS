import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService
    @AppStorage("showsCalendarEvents") private var showsCalendarEvents = false

    @State private var draft: TaskItem
    @State private var showsDeleteConfirmation = false
    @State private var scheduleConflict: ScheduleConflict?
    @State private var isSaving = false
    @State private var calendarMessage: String?

    let isNew: Bool
    private let originalTask: TaskItem

    init(task: TaskItem, isNew: Bool) {
        _draft = State(initialValue: task)
        self.isNew = isNew
        self.originalTask = task
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(editorItemName, text: $draft.title)
                        .font(.headline)

                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Details") {
                    Toggle("Important", isOn: $draft.isImportant)

                    Picker("Project or list", selection: $draft.projectID) {
                        Text("No project or list").tag(nil as UUID?)
                        ForEach(store.orderedProjects) { project in
                            Label(project.name, systemImage: project.kind.systemImage)
                                .tag(project.id as UUID?)
                        }
                    }

                    Picker("Expected duration", selection: $draft.expectedDurationMinutes) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text(durationLabel(minutes)).tag(minutes)
                        }
                    }
                }

                Section {
                    Toggle("Add to schedule", isOn: scheduleBinding)

                    if draft.scheduledAt != nil {
                        DatePicker(
                            "Start",
                            selection: scheduledDateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        if let endDate {
                            LabeledContent("Expected finish") {
                                Text(endDate.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle("Notify me at this time", isOn: $draft.notifiesAtScheduledTime)

                        Picker("Repeat", selection: $draft.recurrence) {
                            ForEach(RecurrenceRule.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }

                        if draft.isRecurring {
                            Label("Completing it advances the task to its next occurrence.", systemImage: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Scheduling is optional. Listello checks the chosen time against other tasks and any calendar events you have allowed it to see.")
                }

                if !isNew, draft.scheduledAt != nil {
                    Section("Apple Calendar") {
                        Button {
                            exportToCalendar()
                        } label: {
                            Label(
                                calendarButtonTitle,
                                systemImage: "calendar.badge.plus"
                            )
                        }

                        if draft.calendarEventIdentifier != nil {
                            Label("This task has been sent to Calendar", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.listelloTeal)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ListelloBackground())
            .navigationTitle(isNew ? L10n.text("New Task") : editorItemName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { checkAndSave() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("This time overlaps", isPresented: conflictPresented, titleVisibility: .visible) {
                if let conflict = scheduleConflict {
                    Button(L10n.format("use_time", conflict.suggestedStart.formatted(date: .abbreviated, time: .shortened))) {
                        draft.scheduledAt = conflict.suggestedStart
                        saveDirectly()
                    }
                    Button(L10n.format("keep_time", conflict.chosenStart.formatted(date: .omitted, time: .shortened))) {
                        saveDirectly()
                    }
                    Button("Cancel", role: .cancel) { scheduleConflict = nil }
                }
            } message: {
                if let conflict = scheduleConflict {
                    Text(L10n.format("schedule_conflict_message", conflict.conflictingTitle))
                }
            }
            .confirmationDialog(
                L10n.text(originalTask.isRecurring ? "Delete recurring task?" : "Delete this task?"),
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if originalTask.isRecurring {
                    Button("Delete This Occurrence", role: .destructive) {
                        deleteOccurrence()
                    }
                    Button("Delete All Future Occurrences", role: .destructive) {
                        deleteTaskSeries()
                    }
                } else {
                    Button("Delete Task", role: .destructive) {
                        deleteTask()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if originalTask.isRecurring {
                    Text("Keep the series going, or remove the recurring task completely.")
                }
            }
            .alert("Calendar", isPresented: calendarMessagePresented) {
                Button("OK", role: .cancel) { calendarMessage = nil }
            } message: {
                Text(calendarMessage ?? "")
            }
        }
    }

    private var endDate: Date? {
        guard let start = draft.scheduledAt, let minutes = draft.expectedDurationMinutes else { return nil }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private var editorItemName: String {
        guard store.project(withID: draft.projectID)?.kind == .list else { return L10n.text("Task") }
        return L10n.text("item").localizedCapitalized
    }

    private var scheduleBinding: Binding<Bool> {
        Binding(
            get: { draft.scheduledAt != nil },
            set: { enabled in
                if enabled {
                    draft.scheduledAt = store.suggestedScheduleTime(on: Date(), excluding: draft.id)
                    draft.notifiesAtScheduledTime = store.preferences.notifyNewScheduledTasks
                } else {
                    draft.scheduledAt = nil
                    draft.notifiesAtScheduledTime = false
                    draft.recurrence = .none
                }
            }
        )
    }

    private var scheduledDateBinding: Binding<Date> {
        Binding(
            get: { draft.scheduledAt ?? Date() },
            set: { draft.scheduledAt = $0 }
        )
    }

    private var conflictPresented: Binding<Bool> {
        Binding(
            get: { scheduleConflict != nil },
            set: { if !$0 { scheduleConflict = nil } }
        )
    }

    private var calendarMessagePresented: Binding<Bool> {
        Binding(
            get: { calendarMessage != nil },
            set: { if !$0 { calendarMessage = nil } }
        )
    }

    private func durationLabel(_ minutes: Int?) -> String {
        guard let minutes else { return L10n.text("No estimate") }
        return L10n.duration(minutes)
    }

    private var durationOptions: [Int?] {
        var options = store.preferences.durationOptions
        if let current = draft.expectedDurationMinutes, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return [nil] + options.map(Optional.some)
    }

    private var calendarButtonTitle: String {
        if draft.isRecurring { return L10n.text("Add This Occurrence to Calendar") }
        return L10n.text(draft.calendarEventIdentifier == nil ? "Add to Calendar" : "Add Another Calendar Event")
    }

    private func checkAndSave() {
        isSaving = true
        Task {
            let calendarEntries: [CalendarEntry]
            if showsCalendarEvents, let scheduledAt = draft.scheduledAt, calendarService.hasFullAccess {
                calendarEntries = await calendarService.entries(on: scheduledAt, requestAccess: false)
            } else {
                calendarEntries = []
            }

            if let conflict = store.scheduleConflict(for: draft, calendarEntries: calendarEntries) {
                scheduleConflict = conflict
                isSaving = false
            } else {
                await persistAndDismiss()
            }
        }
    }

    private func saveDirectly() {
        scheduleConflict = nil
        isSaving = true
        Task { await persistAndDismiss() }
    }

    private func persistAndDismiss() async {
        await store.saveTask(draft)
        isSaving = false
        dismiss()
    }

    private func exportToCalendar() {
        Task {
            guard let identifier = await calendarService.export(draft) else {
                calendarMessage = L10n.text("Calendar access is needed, or no writable calendar is available. You can change access in iPhone Settings.")
                return
            }
            draft.calendarEventIdentifier = identifier
            await store.saveTask(draft)
            calendarMessage = L10n.text("Added to Apple Calendar.")
        }
    }

    private func deleteTask() {
        Task {
            _ = await calendarService.deleteEvent(for: originalTask)
            store.deleteTask(originalTask)
            dismiss()
        }
    }

    private func deleteOccurrence() {
        Task {
            _ = await calendarService.deleteEvent(for: originalTask)
            store.deleteRecurringOccurrence(originalTask)
            dismiss()
        }
    }

    private func deleteTaskSeries() {
        let storedTask = store.task(withID: originalTask.id) ?? originalTask
        Task {
            _ = await calendarService.deleteEvent(for: storedTask)
            store.deleteTask(originalTask)
            dismiss()
        }
    }
}
