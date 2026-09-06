import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var mode: TaskListMode = .active
    @State private var query = ""
    @State private var newTaskTitle = ""
    @State private var editingTask: TaskItem?
    @State private var suggestion: TaskItem?

    private var visibleTasks: [TaskItem] {
        store.filteredTasks(mode: mode, query: query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tasks", selection: $mode) {
                    ForEach(TaskListMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                taskList
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Quiet List")
            .toolbar {
                if mode == .active, !store.activeTasks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            suggestion = store.suggestedTask()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .accessibilityLabel("Pick one task")
                    }
                }

                if mode == .completed, !store.completedTasks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { store.clearCompleted() }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tasks")
            .safeAreaInset(edge: .bottom) {
                if mode == .active {
                    quickAddBar
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(
                    task: task,
                    isNew: false,
                    onSave: { await store.saveTask($0) },
                    onDelete: store.deleteTask
                )
            }
            .sheet(item: $suggestion) { task in
                SuggestionSheet(
                    task: task,
                    nextSuggestion: { store.suggestedTask(excluding: $0) },
                    complete: store.toggleCompleted
                )
            }
        }
    }

    private var taskList: some View {
        List {
            ForEach(visibleTasks) { task in
                TaskRow(task: task) {
                    withAnimation { store.toggleCompleted(task) }
                }
                .onTapGesture { editingTask = task }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation { store.toggleCompleted(task) }
                    } label: {
                        Label(task.isCompleted ? "Restore" : "Done", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(.quietSage)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        withAnimation { store.deleteTask(task) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? emptyTitle : "No Matches",
                    systemImage: mode == .active ? "checkmark.circle" : "archivebox",
                    description: Text(query.isEmpty ? emptyMessage : "Try a different search.")
                )
            }
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            TextField("Add a task", text: $newTaskTitle)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.quietSage, in: Circle())
                    .foregroundStyle(.white)
            }
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add task")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var emptyTitle: String {
        mode == .active ? "Nothing to do" : "Nothing completed yet"
    }

    private var emptyMessage: String {
        mode == .active ? "Add a task below. Scheduling is always optional." : "Completed tasks will appear here."
    }

    private func addTask() {
        guard store.addTask(title: newTaskTitle) != nil else { return }
        newTaskTitle = ""
    }
}
