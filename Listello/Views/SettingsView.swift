import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.replayListelloTutorial) private var replayTutorial
    @State private var showsArchiveAllConfirmation = false
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var pendingBackup: ListelloBackup?
    @State private var showsRestoreConfirmation = false
    @State private var backupErrorMessage: String?

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

                        Section(ListelloTutorialL10n.text("Help")) {
                            Button(action: replayTutorial) {
                                Label(ListelloTutorialL10n.text("Replay tutorial"), systemImage: "questionmark.circle")
                            }
                            .listelloTutorialTarget(.replay)
                        }

                        Section {
                            LabeledContent {
                                Text(store.cloudSyncStatus.title)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("iCloud Sync", systemImage: store.cloudSyncStatus.systemImage)
                            }

                            Button("Sync Now", systemImage: "arrow.clockwise") {
                                store.syncNow()
                            }
                            .disabled(store.cloudSyncStatus == .syncing || store.cloudSyncStatus == .starting)
                        } header: {
                            Text("iCloud Sync")
                        } footer: {
                            Text("Tasks, projects and schedules sync privately across devices signed in to the same Apple Account.")
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
                            Button("Export Full Backup", systemImage: "square.and.arrow.up") {
                                showsBackupExporter = true
                            }

                            Button("Restore from Backup", systemImage: "square.and.arrow.down") {
                                showsBackupImporter = true
                            }
                        } header: {
                            Text("Backup")
                        } footer: {
                            Text("A backup includes every task, project, list, schedule, break, archive and preference. Calendar links remain specific to each device.")
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
                            Label("Your data stays private on your devices and in your iCloud account", systemImage: "lock.shield")
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
            .fileExporter(
                isPresented: $showsBackupExporter,
                document: ListelloBackupDocument(backup: store.makeBackup()),
                contentType: .listelloBackup,
                defaultFilename: backupFilename
            ) { result in
                if case .failure(let error) = result {
                    backupErrorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showsBackupImporter,
                allowedContentTypes: [.listelloBackup, .json],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { throw CocoaError(.fileNoSuchFile) }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    pendingBackup = try ListelloBackup(from: Data(contentsOf: url))
                    showsRestoreConfirmation = true
                } catch {
                    backupErrorMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Replace Listello with this backup?",
                isPresented: $showsRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore Backup", role: .destructive) {
                    if let pendingBackup { store.restoreBackup(pendingBackup) }
                    pendingBackup = nil
                }
                Button("Cancel", role: .cancel) { pendingBackup = nil }
            } message: {
                if let pendingBackup {
                    Text(L10n.format(
                        "backup_restore_summary",
                        pendingBackup.state.tasks.count,
                        pendingBackup.state.projects.count
                    ))
                }
            }
            .alert("Backup Error", isPresented: backupErrorPresented) {
                Button("OK") { backupErrorMessage = nil }
            } message: {
                Text(backupErrorMessage ?? "The backup could not be read.")
            }
        }
    }

    private var backupErrorPresented: Binding<Bool> {
        Binding(
            get: { backupErrorMessage != nil },
            set: { if !$0 { backupErrorMessage = nil } }
        )
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

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Listello Backup \(formatter.string(from: Date()))"
    }

    private func durationLabel(_ minutes: Int) -> String {
        L10n.duration(minutes)
    }
}
