import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService

    @State private var mode: TaskListMode = .active
    @State private var query = ""
    @State private var newTaskTitle = ""
    @State private var selectedProjectID: UUID?
    @State private var showsProjects = false
    @State private var editingTask: TaskItem?
    @State private var suggestion: TaskItem?
    @State private var taskPendingDeletion: TaskItem?

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
                            Text(modeTitle(option)).tag(option)
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

                ToolbarItem(placement: .topBarTrailing) {
                    if mode == .active, !visibleTasks.isEmpty {
                        Button {
                            suggestion = store.suggestedTask(from: visibleTasks)
                        } label: {
                            Image(systemName: "dice.fill")
                        }
                        .accessibilityLabel("Random pick")
                    }
                }
            }
            .searchable(
                text: $query,
                prompt: L10n.text(selectedProject?.kind == .list ? "Search items" : "Search tasks")
            )
            .safeAreaInset(edge: .bottom) {
                if mode == .active {
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
                    complete: completeTask
                )
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
        }
    }

    private var taskList: some View {
        List {
            ForEach(visibleTasks) { task in
                TaskRow(
                    task: task,
                    project: store.project(withID: task.projectID),
                    showsNotes: store.preferences.showNotesInList,
                    reorderIdentifier: mode == .active ? "task:\(task.id.uuidString)" : nil
                ) {
                    completeTask(task)
                }
                .onTapGesture {
                    editingTask = task
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        completeTask(task)
                    } label: {
                        Label(L10n.text(task.isCompleted ? "Restore" : "Done"), systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
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
                .dropDestination(for: String.self) { identifiers, _ in
                    guard
                        mode == .active,
                        let identifier = identifiers.first,
                        identifier.hasPrefix("task:"),
                        let draggedID = UUID(uuidString: String(identifier.dropFirst(5)))
                    else { return false }
                    withAnimation(.snappy) {
                        store.moveTask(draggedID, relativeTo: task.id, within: visibleTasks)
                    }
                    return true
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? emptyTitle : L10n.text("No Matches"),
                    systemImage: mode == .active ? "checkmark.circle" : "archivebox",
                    description: Text(query.isEmpty ? emptyMessage : L10n.text("Try a different search."))
                )
            }
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            TextField(
                quickAddPrompt,
                text: $newTaskTitle
            )
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
            .accessibilityLabel(L10n.text(selectedProject?.kind == .list ? "Add item" : "Add task"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        selectedProject?.name ?? L10n.text("Listello")
    }

    private var headerSubtitle: String {
        if let selectedProject {
            let count = store.filteredTasks(mode: .active, query: "", projectID: selectedProject.id).count
            if selectedProject.kind == .list {
                return L10n.format(count == 1 ? "one_item_in_list" : "items_in_list", count)
            }
            return L10n.format(count == 1 ? "one_open_task_in_project" : "open_tasks_in_project", count)
        }
        return L10n.text("Plan simply. Get things done.")
    }

    private var quickAddColor: Color {
        selectedProject?.color.tint ?? .listelloTeal
    }

    private var emptyTitle: String {
        if selectedProject?.kind == .list, mode == .active { return L10n.text("No items yet") }
        return L10n.text(mode == .active ? "Nothing to do" : "Nothing completed yet")
    }

    private var emptyMessage: String {
        if mode == .active, selectedProject != nil {
            return L10n.text(selectedProject?.kind == .list
                ? "Add the first item to this list below."
                : "Add the first task for this project below.")
        }
        return L10n.text(mode == .active ? "Add a task below. Scheduling is always optional." : "Completed tasks will appear here.")
    }

    private func addTask() {
        guard store.addTask(
            title: newTaskTitle,
            projectID: selectedProjectID,
            usesDefaultDuration: selectedProject?.kind != .list
        ) != nil else { return }
        newTaskTitle = ""
    }

    private var quickAddPrompt: String {
        guard let selectedProject else { return L10n.text("Add a task") }
        return L10n.format(
            selectedProject.kind == .list ? "add_to_list" : "add_to_project",
            selectedProject.name
        )
    }

    private func modeTitle(_ option: TaskListMode) -> String {
        guard option == .active, let selectedProject else { return option.title }
        return L10n.text(selectedProject.kind == .list ? "Items" : "Tasks")
    }

    private func completeTask(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.toggleCompleted(task) }
        }
    }

    private func deleteTask(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.deleteTask(task) }
        }
    }

    private func deleteOccurrence(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.deleteRecurringOccurrence(task) }
        }
    }

    private func deleteSeries(_ task: TaskItem) {
        let storedTask = store.task(withID: task.id) ?? task
        Task {
            _ = await calendarService.deleteEvent(for: storedTask)
            withAnimation { store.deleteTask(task) }
        }
    }
}
