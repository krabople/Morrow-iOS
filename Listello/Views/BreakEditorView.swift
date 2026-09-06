import SwiftUI

struct BreakEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService
    @AppStorage("showsCalendarEvents") private var showsCalendarEvents = false

    @State private var draft: ScheduleBreakItem
    @State private var conflict: ScheduleConflict?
    @State private var showsDeleteConfirmation = false
    @State private var isSaving = false

    let isNew: Bool

    init(scheduleBreak: ScheduleBreakItem, isNew: Bool) {
        _draft = State(initialValue: scheduleBreak)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Break name", text: $draft.title)
                        .font(.headline)
                }

                Section("Schedule") {
                    DatePicker(
                        "Start",
                        selection: $draft.startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("Duration", selection: $draft.durationMinutes) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text(L10n.duration(minutes)).tag(minutes)
                        }
                    }

                    LabeledContent("Expected finish") {
                        Text(draft.endDate.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Label(
                        "Breaks block out time in your schedule without becoming tasks.",
                        systemImage: "cup.and.saucer.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !isNew {
                    Section {
                        Button("Delete Break", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(L10n.text(isNew ? "New Break" : "Edit Break"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { checkAndSave() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .confirmationDialog("This time overlaps", isPresented: conflictPresented, titleVisibility: .visible) {
                if let conflict {
                    Button(L10n.format("use_time", conflict.suggestedStart.formatted(date: .abbreviated, time: .shortened))) {
                        draft.startDate = conflict.suggestedStart
                        save()
                    }
                    Button(L10n.format("keep_time", conflict.chosenStart.formatted(date: .omitted, time: .shortened))) {
                        save()
                    }
                    Button("Cancel", role: .cancel) { self.conflict = nil }
                }
            } message: {
                if let conflict {
                    Text(L10n.format("schedule_conflict_message", conflict.conflictingTitle))
                }
            }
            .confirmationDialog("Delete this break?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Break", role: .destructive) {
                    store.deleteBreak(draft)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var durationOptions: [Int] {
        Array(Set(store.preferences.durationOptions + [draft.durationMinutes])).sorted()
    }

    private var conflictPresented: Binding<Bool> {
        Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })
    }

    private func checkAndSave() {
        isSaving = true
        Task {
            let entries: [CalendarEntry]
            if showsCalendarEvents, calendarService.hasFullAccess {
                entries = await calendarService.entries(on: draft.startDate, requestAccess: false)
            } else {
                entries = []
            }
            if let found = store.scheduleConflict(for: draft, calendarEntries: entries) {
                conflict = found
                isSaving = false
            } else {
                save()
            }
        }
    }

    private func save() {
        conflict = nil
        store.saveBreak(draft)
        isSaving = false
        dismiss()
    }
}
