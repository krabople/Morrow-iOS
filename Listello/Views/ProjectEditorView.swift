import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectItem

    let isNew: Bool
    let onSave: (ProjectItem) -> Void

    init(project: ProjectItem, isNew: Bool, onSave: @escaping (ProjectItem) -> Void) {
        _draft = State(initialValue: project)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $draft.name)
                        .font(.headline)
                }

                Section("Colour") {
                    HStack(spacing: 14) {
                        ForEach(ProjectColor.allCases) { color in
                            Button {
                                draft.color = color
                            } label: {
                                Circle()
                                    .fill(color.tint)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if draft.color == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(Color.primary.opacity(draft.color == color ? 0.30 : 0), lineWidth: 3)
                                            .padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("colour_\(color.rawValue)"))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(L10n.text(isNew ? "New Project" : "Edit Project"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
