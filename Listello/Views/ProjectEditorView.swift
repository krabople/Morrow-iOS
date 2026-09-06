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
                    TextField(namePrompt, text: $draft.name)
                        .font(.headline)
                }

                Section("Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ProjectKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: draft.kind) { _, kind in
                        draft.hidesFromAllTasks = kind == .list
                    }
                }

                Section {
                    Toggle("Hide from All Tasks", isOn: $draft.hidesFromAllTasks)
                } footer: {
                    Text(visibilityExplanation)
                }

                Section("Colour") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 18) {
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
            .navigationTitle(editorTitle)
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

    private var editorTitle: String {
        if isNew { return L10n.text(draft.kind == .list ? "New List" : "New Project") }
        return L10n.text(draft.kind == .list ? "Edit List" : "Edit Project")
    }

    private var namePrompt: String {
        L10n.text(draft.kind == .list ? "List name" : "Project name")
    }

    private var visibilityExplanation: String {
        if draft.kind == .list {
            return L10n.text("Lists are hidden from All Tasks by default. You can still open them from the sidebar.")
        }
        return L10n.text("Hidden projects stay in the sidebar, but their tasks do not appear in All Tasks.")
    }
}
