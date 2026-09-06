import SwiftUI
import UIKit

struct ProjectsSidebar: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var selectedProjectID: UUID?
    @Binding var isPresented: Bool

    @State private var editingProject: ProjectItem?
    @State private var newProject: ProjectItem?
    @State private var projectToDelete: ProjectItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ListelloMark(size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Listello")
                        .font(.title2.bold())
                        .foregroundStyle(Color.listelloInk)
                    Text("Projects and lists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close projects and lists")
            }
            .padding(20)

            Divider()

            List {
                selectionRow(
                    title: L10n.text("All Tasks"),
                    systemImage: "tray.full.fill",
                    color: .listelloTeal,
                    count: store.activeTasks.count,
                    isSelected: selectedProjectID == nil
                ) {
                    select(nil)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(store.orderedProjects) { project in
                    projectRow(project)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            Button {
                newProject = ProjectItem(name: "", color: nextColor)
            } label: {
                Label("New project or list", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .foregroundStyle(Color.listelloTeal)
        }
        .frame(width: min(350, UIScreen.main.bounds.width * 0.90))
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.18), radius: 28, x: 8)
        .sheet(item: $newProject) { project in
            ProjectEditorView(project: project, isNew: true) { updated in
                if let created = store.addProject(
                    name: updated.name,
                    color: updated.color,
                    kind: updated.kind,
                    hidesFromAllTasks: updated.hidesFromAllTasks
                ) {
                    select(created.id)
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project, isNew: false, onSave: store.saveProject)
        }
        .confirmationDialog(
            L10n.format("delete_project_named", projectToDelete?.name ?? L10n.text("this project or list")),
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let project = projectToDelete {
                if project.hidesFromAllTasks {
                    Button(archiveAndDeleteLabel(for: project), role: .destructive) {
                        delete(project, disposition: .archiveContents)
                    }
                } else {
                    Button(keepUnassignedLabel(for: project)) {
                        delete(project, disposition: .keepUnassigned)
                    }
                    Button(archiveAndDeleteLabel(for: project), role: .destructive) {
                        delete(project, disposition: .archiveContents)
                    }
                }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            if let project = projectToDelete {
                Text(deletionMessage(for: project))
            }
        }
    }

    private func projectRow(_ project: ProjectItem) -> some View {
        HStack(spacing: 0) {
            Button {
                select(project.id)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: project.kind.systemImage)
                        .foregroundStyle(project.color.tint)
                        .frame(width: 19)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.listelloInk)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(project.kind.title)
                            if project.hidesFromAllTasks {
                                Image(systemName: "eye.slash")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(store.filteredTasks(mode: .active, query: "", projectID: project.id).count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.leading, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit", systemImage: "pencil") { editingProject = project }
                Button("Delete", systemImage: "trash", role: .destructive) { projectToDelete = project }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 40, height: 44)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
                .draggable("project:\(project.id.uuidString)") {
                    Label(project.name, systemImage: project.kind.systemImage)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Reorder")
        }
        .contentShape(Rectangle())
        .background(
            project.color.tint.opacity(selectedProjectID == project.id ? 0.17 : 0.055),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            if selectedProjectID == project.id {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(project.color.tint.opacity(0.45), lineWidth: 1)
            }
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard
                let identifier = identifiers.first,
                identifier.hasPrefix("project:"),
                let draggedID = UUID(uuidString: String(identifier.dropFirst(8)))
            else { return false }
            withAnimation(.snappy) {
                store.moveProject(draggedID, relativeTo: project.id)
            }
            return true
        }
    }

    private func selectionRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .frame(width: 19)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.listelloInk)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .contentShape(Rectangle())
            .background(color.opacity(isSelected ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var nextColor: ProjectColor {
        let colors = ProjectColor.allCases
        return colors[store.projects.count % colors.count]
    }

    private func archiveAndDeleteLabel(for project: ProjectItem) -> String {
        L10n.text(project.kind == .list ? "Archive Items and Delete List" : "Archive Tasks and Delete Project")
    }

    private func keepUnassignedLabel(for project: ProjectItem) -> String {
        L10n.text(project.kind == .list ? "Keep Items in All Tasks" : "Keep Tasks in All Tasks")
    }

    private func deletionMessage(for project: ProjectItem) -> String {
        if project.hidesFromAllTasks {
            return L10n.text(project.kind == .list
                ? "Because this list is hidden from All Tasks, all of its items will be archived."
                : "Because this project is hidden from All Tasks, all of its tasks will be archived.")
        }
        return L10n.text(project.kind == .list
            ? "Choose whether to archive this list’s items or keep them in All Tasks as unassigned."
            : "Choose whether to archive this project’s tasks or keep them in All Tasks as unassigned.")
    }

    private func delete(_ project: ProjectItem, disposition: ProjectDeletionDisposition) {
        if selectedProjectID == project.id { selectedProjectID = nil }
        store.deleteProject(project, disposition: disposition)
        projectToDelete = nil
    }

    private func select(_ projectID: UUID?) {
        selectedProjectID = projectID
        withAnimation(.snappy) { isPresented = false }
    }
}
