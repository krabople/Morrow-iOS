import SwiftUI
import UIKit

struct RemindersImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var remindersService: RemindersService

    @State private var sourceLists: [ReminderSourceList] = []
    @State private var choices: [String: ImportChoice] = [:]
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var accessDenied = false
    @State private var importedCount: Int?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading Reminders lists…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if accessDenied {
                ContentUnavailableView {
                    Label("Reminders Access Needed", systemImage: "checklist")
                } description: {
                    Text("Allow full Reminders access for Listello in iPhone Settings to import your lists.")
                } actions: {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if sourceLists.isEmpty {
                ContentUnavailableView(
                    "No Reminders Lists",
                    systemImage: "checklist",
                    description: Text("Create a list in Apple Reminders, then return here to import it.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(sourceLists) { sourceList in
                        reminderListRow(sourceList)
                    }
                } header: {
                    Text("Choose Lists")
                } footer: {
                    Text("Only incomplete reminders are copied. Your original Reminders lists are not changed.")
                }
            }
        }
        .navigationTitle("Import from Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { Task { await importSelectedLists() } }
                    .fontWeight(.semibold)
                    .disabled(selectedCount == 0 || isImporting)
            }
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView("Importing…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .task { await loadLists() }
        .alert(
            "Import Complete",
            isPresented: Binding(
                get: { importedCount != nil },
                set: { if !$0 { importedCount = nil } }
            )
        ) {
            Button("Done") { dismiss() }
        } message: {
            Text(L10n.format("imported_reminders_summary", importedCount ?? 0, selectedCount))
        }
    }

    private func reminderListRow(_ sourceList: ReminderSourceList) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: selectedBinding(for: sourceList.id)) {
                Label {
                    Text(sourceList.title)
                        .font(.body.weight(.semibold))
                } icon: {
                    Image(systemName: "list.bullet.circle.fill")
                        .foregroundStyle(Color(hex: sourceList.colorHex))
                }
            }

            if choices[sourceList.id]?.isSelected == true {
                Picker("Import as", selection: kindBinding(for: sourceList.id)) {
                    ForEach(ProjectKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 5)
    }

    private var selectedCount: Int {
        choices.values.filter(\.isSelected).count
    }

    private func selectedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { choices[id]?.isSelected ?? false },
            set: { newValue in
                var choice = choices[id] ?? ImportChoice()
                choice.isSelected = newValue
                choices[id] = choice
            }
        )
    }

    private func kindBinding(for id: String) -> Binding<ProjectKind> {
        Binding(
            get: { choices[id]?.kind ?? .list },
            set: { newValue in
                var choice = choices[id] ?? ImportChoice()
                choice.kind = newValue
                choices[id] = choice
            }
        )
    }

    private func loadLists() async {
        isLoading = true
        let granted = await remindersService.requestFullAccess()
        accessDenied = !granted
        if granted {
            sourceLists = remindersService.sourceLists()
            for sourceList in sourceLists where choices[sourceList.id] == nil {
                choices[sourceList.id] = ImportChoice()
            }
        }
        isLoading = false
    }

    private func importSelectedLists() async {
        let selections = sourceLists.filter { choices[$0.id]?.isSelected == true }
        guard !selections.isEmpty else { return }
        isImporting = true
        var total = 0

        for (offset, sourceList) in selections.enumerated() {
            let kind = choices[sourceList.id]?.kind ?? .list
            let color = ProjectColor.allCases[(store.projects.count + offset) % ProjectColor.allCases.count]
            guard let destination = store.addProject(
                name: sourceList.title,
                color: color,
                kind: kind,
                hidesFromAllTasks: kind == .list
            ) else { continue }
            let reminders = await remindersService.incompleteReminders(in: sourceList.id)
            total += store.importReminders(reminders, into: destination)
        }

        isImporting = false
        importedCount = total
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct ImportChoice {
    var isSelected = false
    var kind: ProjectKind = .list
}
