import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var mode: TaskListMode = .active
    @State private var query = ""
    @State private var newTaskTitle = ""
    @State private var selectedProjectID: UUID?
    @State private var showsProjects = false
    @State private var editingTask: TaskItem?
    @State private var suggestion: TaskItem?
    @State private var editMode: EditMode = .inactive

    private var selectedProject: ProjectItem? {
        store.project(withID: selectedProjectID)
    }

    private var visibleTasks: [TaskItem] {
        store.filteredTasks(mode: mode, query: query, projectID: selectedProjectID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ListelloBackground()

                VStack(spacing: 10) {
                    ListelloHeader(title: headerTitle, subtitle: headerSubtitle)
                        .padding(.horizontal)

                    Picker("Tasks", selection: $mode) {
                        ForEach(TaskListMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    taskList
                }

                if showsProjects {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.snappy) { showsProjects = false } }
                        .transition(.opacity)

                    ProjectsSidebar(selectedProjectID: $selectedProjectID, isPresented: $showsProjects)
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
            .navigationTitle("Listello")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy) { showsProjects = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Open projects")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if editMode.isEditing {
                        Button("Done") { withAnimation { editMode = .inactive } }
                            .fontWeight(.semibold)
                    } else {
                        if mode == .active, !visibleTasks.isEmpty {
                            Button("Pick One") {
                                suggestion = store.suggestedTask(from: visibleTasks)
                            }
                            .fontWeight(.semibold)
                        }

                        if (mode == .active && visibleTasks.count > 1) || (mode == .completed && !store.completedTasks.isEmpty) {
                            Menu {
                                if mode == .active, visibleTasks.count > 1 {
                                    Button("Reorder Tasks", systemImage: "arrow.up.arrow.down") {
                                        withAnimation { editMode = .active }
                                    }
                                }
                                if mode == .completed, !store.completedTasks.isEmpty {
                                    Button("Clear Completed", systemImage: "trash", role: .destructive) {
                                        store.clearCompleted()
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("More list actions")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tasks")
            .safeAreaInset(edge: .bottom) {
                if mode == .active, !editMode.isEditing {
                    quickAddBar
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(task: task, isNew: false)
            }
            .sheet(item: $suggestion) { task in
                SuggestionSheet(
                    task: task,
                    nextSuggestion: { excludedID in
                        let current = store.filteredTasks(mode: .active, query: query, projectID: selectedProjectID)
                        return store.suggestedTask(from: current, excluding: excludedID)
                    },
                    complete: store.toggleCompleted
                )
            }
        }
        .environment(\.editMode, $editMode)
    }

    private var taskList: some View {
        List {
            ForEach(visibleTasks) { task in
                TaskRow(task: task, project: store.project(withID: task.projectID)) {
                    withAnimation { store.toggleCompleted(task) }
                }
                .onTapGesture {
                    guard !editMode.isEditing else { return }
                    editingTask = task
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation { store.toggleCompleted(task) }
                    } label: {
                        Label(task.isCompleted ? "Restore" : "Done", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(.listelloTeal)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        withAnimation { store.deleteTask(task) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                guard mode == .active else { return }
                store.moveTasks(from: source, to: destination, within: visibleTasks)
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
            TextField(selectedProject == nil ? "Add a task" : "Add to \(selectedProject?.name ?? "project")", text: $newTaskTitle)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(quickAddColor, in: Circle())
                    .foregroundStyle(.white)
                    .shadow(color: quickAddColor.opacity(0.25), radius: 8, y: 4)
            }
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add task")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        selectedProject?.name ?? "Listello"
    }

    private var headerSubtitle: String {
        if let selectedProject {
            let count = store.activeTasks.filter { $0.projectID == selectedProject.id }.count
            return "\(count) open \(count == 1 ? "task" : "tasks") in this project"
        }
        return "A colourful home for the things that matter"
    }

    private var quickAddColor: Color {
        selectedProject?.color.tint ?? .listelloTeal
    }

    private var emptyTitle: String {
        mode == .active ? "Nothing to do" : "Nothing completed yet"
    }

    private var emptyMessage: String {
        if mode == .active, selectedProject != nil {
            return "Add the first task for this project below."
        }
        return mode == .active ? "Add a task below. Scheduling is always optional." : "Completed tasks will appear here."
    }

    private func addTask() {
        guard store.addTask(title: newTaskTitle, projectID: selectedProjectID) != nil else { return }
        newTaskTitle = ""
    }
}
