import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showsCalendar = false
    @State private var permissionDenied = false
    @State private var editingTask: TaskItem?
    @State private var newTask: TaskItem?

    private var scheduledTasks: [TaskItem] {
        store.tasks(on: selectedDay)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayNavigator
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                List {
                    Section {
                        Toggle(isOn: dayNotificationBinding) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Notifications for this day")
                                Text("Alert me when each scheduled task is due")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        ForEach(scheduledTasks) { task in
                            HStack(alignment: .top, spacing: 14) {
                                Text(task.scheduledAt?.formatted(date: .omitted, time: .shortened) ?? "")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                TaskRow(task: task) {
                                    withAnimation { store.toggleCompleted(task) }
                                }
                            }
                            .onTapGesture { editingTask = task }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { store.toggleCompleted(task) }
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                                .tint(.quietSage)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation { store.deleteTask(task) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Timetable")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .overlay {
                    if scheduledTasks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.quietSage)
                            Text("No plans for this day")
                                .font(.headline)
                            Text("Your normal task list still works without a schedule.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 90)
                        .padding(.horizontal, 36)
                        .allowsHitTesting(false)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newTask = TaskItem(
                            title: "",
                            scheduledAt: store.suggestedScheduleTime(on: selectedDay)
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add scheduled task")
                }
            }
            .sheet(isPresented: $showsCalendar) {
                NavigationStack {
                    DatePicker("Choose a day", selection: $selectedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Choose a Day")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCalendar = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(
                    task: task,
                    isNew: false,
                    onSave: { await store.saveTask($0) },
                    onDelete: store.deleteTask
                )
            }
            .sheet(item: $newTask) { task in
                TaskEditorView(
                    task: task,
                    isNew: true,
                    onSave: { await store.saveTask($0) },
                    onDelete: { _ in }
                )
            }
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Allow notifications for Quiet List in iPhone Settings to use this option.")
            }
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button {
                moveDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            Button {
                showsCalendar = true
            } label: {
                VStack(spacing: 2) {
                    Text(dayTitle)
                        .font(.headline)
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose date")

            Spacer()

            Button {
                moveDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next day")
        }
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "Today" }
        if Calendar.current.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.day().month(.abbreviated))
    }

    private var dayNotificationBinding: Binding<Bool> {
        Binding(
            get: { store.isDayNotificationsEnabled(selectedDay) },
            set: { enabled in
                Task {
                    let succeeded = await store.setDayNotifications(enabled, for: selectedDay)
                    if enabled && !succeeded { permissionDenied = true }
                }
            }
        )
    }

    private func moveDay(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: amount, to: selectedDay) else { return }
        withAnimation { selectedDay = next }
    }
}
