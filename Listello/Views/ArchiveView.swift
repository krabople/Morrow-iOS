import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService
    @State private var query = ""
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsDeleteAllConfirmation = false

    private var visibleTasks: [TaskItem] {
        store.filteredArchivedTasks(query: query)
    }

    var body: some View {
        ZStack {
            ListelloBackground()

            List {
                ForEach(visibleTasks) { task in
                    archiveRow(task)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if visibleTasks.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "Archive is empty" : "No Matches",
                        systemImage: "archivebox",
                        description: Text(query.isEmpty ? "Archived tasks will be kept here." : "Try a different search.")
                    )
                }
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search archived tasks")
        .safeAreaInset(edge: .bottom) {
            if !store.archivedTasks.isEmpty {
                HStack(spacing: 12) {
                    Button("Restore All", systemImage: "arrow.uturn.backward") {
                        withAnimation { store.restoreAllArchivedTasks() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.listelloTeal)

                    Button("Delete All", systemImage: "trash", role: .destructive) {
                        showsDeleteAllConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            "Delete this archived task permanently?",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let task = taskPendingDeletion {
                Button("Delete Permanently", role: .destructive) {
                    deleteTask(task)
                    taskPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { taskPendingDeletion = nil }
        }
        .confirmationDialog(
            "Delete every archived task permanently?",
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Permanently", role: .destructive) {
                deleteAllTasks()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func archiveRow(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(task.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.listelloInk)

            HStack(spacing: 8) {
                if task.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle")
                }
                if let project = store.project(withID: task.projectID) {
                    Label(project.name, systemImage: "folder.fill")
                        .foregroundStyle(project.color.tint)
                }
                if task.isRecurring {
                    Label(task.recurrence.title, systemImage: "repeat")
                        .foregroundStyle(Color.listelloCoral)
                }
            }
            .font(.caption2.weight(.semibold))

            if let archivedAt = task.archivedAt {
                Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    withAnimation { store.restoreArchivedTask(task) }
                }
                .foregroundStyle(Color.listelloTeal)

                Button("Delete", systemImage: "trash", role: .destructive) {
                    taskPendingDeletion = task
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color.listelloViolet.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.listelloViolet)
                .frame(width: 4)
                .padding(.vertical, 12)
        }
    }

    private func deleteTask(_ task: TaskItem) {
        Task {
            _ = await calendarService.deleteEvent(for: task)
            withAnimation { store.deleteTask(task) }
        }
    }

    private func deleteAllTasks() {
        let archivedTasks = store.archivedTasks
        Task {
            await calendarService.deleteEvents(for: archivedTasks)
            withAnimation { store.deleteAllArchivedTasks() }
        }
    }
}
