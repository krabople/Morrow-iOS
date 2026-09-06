import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskItem
    @State private var showsDeleteConfirmation = false

    let isNew: Bool
    let onSave: (TaskItem) async -> Void
    let onDelete: (TaskItem) -> Void

    init(
        task: TaskItem,
        isNew: Bool,
        onSave: @escaping (TaskItem) async -> Void,
        onDelete: @escaping (TaskItem) -> Void
    ) {
        _draft = State(initialValue: task)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task", text: $draft.title)
                        .font(.headline)

                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Toggle("Important", isOn: $draft.isImportant)

                    Toggle("Add to schedule", isOn: scheduleBinding)

                    if draft.scheduledAt != nil {
                        DatePicker(
                            "Date and time",
                            selection: scheduledDateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        Toggle("Notify me at this time", isOn: $draft.notifiesAtScheduledTime)
                    }
                } footer: {
                    Text("Scheduling is optional. Notifications stay off unless you choose them here or enable them for the whole day.")
                }

                if !isNew {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(draft)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Task", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
            }
        }
    }

    private var scheduleBinding: Binding<Bool> {
        Binding(
            get: { draft.scheduledAt != nil },
            set: { enabled in
                if enabled {
                    draft.scheduledAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
                } else {
                    draft.scheduledAt = nil
                    draft.notifiesAtScheduledTime = false
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
}
