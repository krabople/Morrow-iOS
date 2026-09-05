import SwiftUI

struct AddTaskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var dueChoice = "Today"
    @State private var duration = 30
    @State private var priority = TaskPriority.important
    @State private var energy = EnergyLevel.medium
    @State private var project = "Personal"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical).font(.headline)
                    TextField("Notes or useful context", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section("Plan") {
                    Picker("When", selection: $dueChoice) { ForEach(["Today", "Tomorrow", "This week", "Someday"], id: \.self) { Text($0) } }
                    Picker("Duration", selection: $duration) { ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { Text("\($0) min") } }
                    Picker("Priority", selection: $priority) { ForEach(TaskPriority.allCases) { Text($0.title).tag($0) } }
                    Picker("Energy", selection: $energy) { ForEach(EnergyLevel.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                    Picker("Space", selection: $project) { ForEach(["Inbox", "Northstar", "Personal", "People", "Wellbeing", "Admin"], id: \.self) { Text($0) } }
                }
                Section("More") {
                    Label("Add reminder", systemImage: "bell")
                    Label("Add location", systemImage: "location")
                    Label("Add tags", systemImage: "tag")
                    Label("Add subtasks", systemImage: "checklist")
                    Label("Attach a file", systemImage: "paperclip")
                }
            }
            .navigationTitle("Add a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: addTask).fontWeight(.bold).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func addTask() {
        var dueDate: Date?
        switch dueChoice {
        case "Today": dueDate = Date()
        case "Tomorrow": dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        case "This week": dueDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        default: dueDate = nil
        }
        model.add(TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, dueDate: dueDate, durationMinutes: duration, project: project, priority: priority, energy: energy))
        dismiss()
    }
}

struct RandomPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var maxMinutes = 30
    @State private var energy = EnergyLevel.medium
    @State private var picked: TaskItem?
    @State private var shuffleCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "shuffle").font(.title2).foregroundStyle(.white).frame(width: 52, height: 52).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 17))
                    Text("Let chance break the tie.").font(.title2.bold()).foregroundStyle(.white)
                    Text("Morrow only chooses something that fits the time and energy you have.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity).padding(24).background(MorrowTheme.forest, in: RoundedRectangle(cornerRadius: 24))

                if let picked {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR NUDGE").font(.caption2.bold()).tracking(1).foregroundStyle(MorrowTheme.secondary)
                        Text(picked.title).font(.title3.bold())
                        Text("\(picked.durationMinutes) min · \(picked.energy.rawValue) energy · \(picked.project)").font(.caption).foregroundStyle(MorrowTheme.secondary)
                        Text("Suggested because it fits your capacity and is still open.").font(.caption).foregroundStyle(MorrowTheme.secondary).padding(10).background(MorrowTheme.canvas, in: RoundedRectangle(cornerRadius: 11))
                    }.morrowCard()
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Time available").font(.caption.bold())
                    Picker("Time", selection: $maxMinutes) { Text("10 min").tag(10); Text("30 min").tag(30); Text("60 min").tag(60) }.pickerStyle(.segmented)
                    Text("Energy right now").font(.caption.bold()).padding(.top, 5)
                    Picker("Energy", selection: $energy) { ForEach(EnergyLevel.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }

                HStack {
                    Button { choose() } label: { Label("Another", systemImage: "arrow.counterclockwise") }.buttonStyle(.bordered)
                    Button {
                        if let picked { model.startFocus(picked) }
                        dismiss()
                    } label: {
                        Label("Start now", systemImage: "play.fill")
                    }
                    .buttonStyle(MorrowButtonStyle())
                    .disabled(picked == nil)
                }
                Spacer()
            }
            .padding(18)
            .background(MorrowTheme.background)
            .navigationTitle("Pick for me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear(perform: choose)
            .sensoryFeedback(.selection, trigger: shuffleCount)
        }
    }

    private func choose() { picked = model.pickTask(maxMinutes: maxMinutes, energy: energy); shuffleCount += 1 }
}

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @State private var draft: TaskItem?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section {
                            TextField("Task", text: binding(\.title), axis: .vertical).font(.headline)
                            TextField("Notes", text: binding(\.notes), axis: .vertical).lineLimit(3...8)
                        }
                        Section("Plan") {
                            DatePicker("Due", selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
                            Stepper("Duration: \(draft.durationMinutes) min", value: binding(\.durationMinutes), in: 5...240, step: 5)
                            Picker("Priority", selection: binding(\.priority)) { ForEach(TaskPriority.allCases) { Text($0.title).tag($0) } }
                            Picker("Energy", selection: binding(\.energy)) { ForEach(EnergyLevel.allCases) { Text($0.rawValue).tag($0) } }
                            Toggle("Flagged", isOn: binding(\.isFlagged))
                            Toggle("Waiting for someone", isOn: binding(\.isWaiting))
                        }
                        Section("Steps") {
                            ForEach(draft.subtasks) { step in
                                Button { toggleSubtask(step.id) } label: { Label(step.title, systemImage: step.isComplete ? "checkmark.circle.fill" : "circle").foregroundStyle(step.isComplete ? MorrowTheme.forest : MorrowTheme.ink) }
                            }
                            Label("Add step", systemImage: "plus").foregroundStyle(MorrowTheme.forest)
                        }
                        Section { Button(role: .destructive) { model.delete(taskID); dismiss() } label: { Label("Delete task", systemImage: "trash") } }
                    }
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder")
                }
            }
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if let draft { model.update(draft) }; dismiss() }.fontWeight(.bold).disabled(draft == nil) }
            }
            .onAppear { draft = model.task(id: taskID) }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaskItem, Value>) -> Binding<Value> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft![keyPath: keyPath] = $0 })
    }

    private var dateBinding: Binding<Date> { Binding(get: { draft?.dueDate ?? Date() }, set: { draft?.dueDate = $0 }) }
    private func toggleSubtask(_ id: UUID) { guard let index = draft?.subtasks.firstIndex(where: { $0.id == id }) else { return }; draft?.subtasks[index].isComplete.toggle() }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let openTask: (TaskItem) -> Void

    private var results: [TaskItem] { query.isEmpty ? Array(model.tasks.prefix(6)) : model.tasks.filter { "\($0.title) \($0.project) \($0.tags.joined(separator: " "))".localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List(results) { task in Button { openTask(task) } label: { VStack(alignment: .leading, spacing: 4) { Text(task.title).foregroundStyle(MorrowTheme.ink); Text("\(task.project) · \(task.dueText)").font(.caption).foregroundStyle(MorrowTheme.secondary) } } }
                .searchable(text: $query, prompt: "Tasks, projects and tags")
                .navigationTitle("Search everything")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
