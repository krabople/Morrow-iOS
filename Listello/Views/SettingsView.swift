import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showsArchiveAllConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                ListelloBackground()

                VStack(spacing: 10) {
                    ListelloHeader(
                        title: L10n.text("Settings"),
                        subtitle: L10n.text("Make Listello work the way you do")
                    )
                    .padding(.horizontal)

                    Form {
                        Section("Appearance") {
                            Picker("Colour mode", selection: appearanceBinding) {
                                ForEach(AppearancePreference.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Task Defaults") {
                            NavigationLink {
                                DurationOptionsView()
                            } label: {
                                LabeledContent("Duration choices", value: "\(store.preferences.durationOptions.count)")
                            }

                            Picker("Default duration", selection: defaultDurationBinding) {
                                ForEach(store.preferences.durationOptions, id: \.self) { minutes in
                                    Text(durationLabel(minutes)).tag(minutes)
                                }
                            }

                            Toggle("Notify newly scheduled tasks", isOn: notifyNewTasksBinding)
                        }

                        Section("List") {
                            Toggle("Put important tasks first", isOn: importantFirstBinding)
                            Toggle("Show task notes", isOn: showNotesBinding)
                        }

                        Section("Import") {
                            NavigationLink {
                                RemindersImportView()
                            } label: {
                                Label("Import from Reminders", systemImage: "checklist")
                            }
                        }

                        Section {
                            Picker("Move completed tasks", selection: archiveDelayBinding) {
                                Text("Never").tag(nil as Int?)
                                Text("Immediately").tag(0 as Int?)
                                Text("After 1 day").tag(1 as Int?)
                                Text("After 7 days").tag(7 as Int?)
                                Text("After 30 days").tag(30 as Int?)
                            }
                        } header: {
                            Text("Completed Tasks")
                        } footer: {
                            Text("Automatically archived tasks remain available and searchable in the Archive.")
                        }

                        Section("Archive") {
                            NavigationLink {
                                ArchiveView()
                            } label: {
                                LabeledContent("View Archive", value: "\(store.archivedTasks.count)")
                            }

                            Button("Archive All Tasks", systemImage: "archivebox") {
                                showsArchiveAllConfirmation = true
                            }
                            .foregroundStyle(Color.listelloViolet)
                            .disabled(!store.tasks.contains(where: { !$0.isArchived }))
                        }

                        Section("About") {
                            LabeledContent("Version", value: appVersion)
                            Label("Tasks stay privately on this device", systemImage: "lock.shield")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Archive every task?",
                isPresented: $showsArchiveAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Archive All Tasks") { store.archiveAllTasks() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your List and Done screens will be emptied. You can restore tasks later from the Archive.")
            }
        }
    }

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(get: { store.preferences.appearance }, set: store.setAppearance)
    }

    private var defaultDurationBinding: Binding<Int> {
        Binding(get: { store.preferences.defaultDurationMinutes }, set: store.setDefaultDuration)
    }

    private var notifyNewTasksBinding: Binding<Bool> {
        Binding(get: { store.preferences.notifyNewScheduledTasks }, set: store.setNotifyNewScheduledTasks)
    }

    private var importantFirstBinding: Binding<Bool> {
        Binding(get: { store.preferences.importantTasksFirst }, set: store.setImportantTasksFirst)
    }

    private var showNotesBinding: Binding<Bool> {
        Binding(get: { store.preferences.showNotesInList }, set: store.setShowNotesInList)
    }

    private var archiveDelayBinding: Binding<Int?> {
        Binding(get: { store.preferences.completedArchiveDelayDays }, set: store.setCompletedArchiveDelayDays)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"
    }

    private func durationLabel(_ minutes: Int) -> String {
        L10n.duration(minutes)
    }
}
