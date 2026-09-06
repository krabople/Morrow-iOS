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
                    Text("Projects")
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
                .accessibilityLabel("Close projects")
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    selectionRow(
                        title: "All Tasks",
                        systemImage: "tray.full.fill",
                        color: .listelloTeal,
                        count: store.activeTasks.count,
                        isSelected: selectedProjectID == nil
                    ) {
                        select(nil)
                    }

                    ForEach(store.projects.sorted { $0.createdAt < $1.createdAt }) { project in
                        projectRow(project)
                    }
                }
                .padding(14)
            }

            Divider()

            Button {
                newProject = ProjectItem(name: "", color: nextColor)
            } label: {
                Label("New Project", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .foregroundStyle(Color.listelloTeal)
        }
        .frame(width: min(330, UIScreen.main.bounds.width * 0.86))
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.18), radius: 28, x: 8)
        .sheet(item: $newProject) { project in
            ProjectEditorView(project: project, isNew: true) { updated in
                if let created = store.addProject(name: updated.name, color: updated.color) {
                    select(created.id)
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project, isNew: false, onSave: store.saveProject)
        }
        .confirmationDialog(
            "Delete \(projectToDelete?.name ?? "this project")?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                guard let project = projectToDelete else { return }
                if selectedProjectID == project.id { selectedProjectID = nil }
                store.deleteProject(project)
                projectToDelete = nil
            }
        } message: {
            Text("Its tasks will remain in All Tasks and become unassigned.")
        }
    }

    private func projectRow(_ project: ProjectItem) -> some View {
        HStack(spacing: 0) {
            Button {
                select(project.id)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(project.color.tint)
                        .frame(width: 12, height: 12)
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.listelloInk)
                        .lineLimit(1)
                    Spacer()
                    Text("\(store.activeTasks.filter { $0.projectID == project.id }.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit", systemImage: "pencil") { editingProject = project }
                Button("Delete", systemImage: "trash", role: .destructive) { projectToDelete = project }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.secondary)
            }
        }
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
                    .frame(width: 16)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.listelloInk)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(color.opacity(isSelected ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var nextColor: ProjectColor {
        let colors = ProjectColor.allCases
        return colors[store.projects.count % colors.count]
    }

    private func select(_ projectID: UUID?) {
        selectedProjectID = projectID
        withAnimation(.snappy) { isPresented = false }
    }
}
