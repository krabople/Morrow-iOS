import SwiftUI

struct CalendarImportView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case day = "One Day"
        case range = "Range"
        case upcoming = "Upcoming"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarService: CalendarService

    @State private var scope: Scope = .day
    @State private var selectedDay: Date
    @State private var rangeStart: Date
    @State private var rangeEnd: Date
    @State private var projectID: UUID?
    @State private var isImporting = false
    @State private var resultMessage: String?

    init(selectedDay: Date) {
        _selectedDay = State(initialValue: selectedDay)
        _rangeStart = State(initialValue: selectedDay)
        _rangeEnd = State(initialValue: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDay) ?? selectedDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Import", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch scope {
                    case .day:
                        DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
                    case .range:
                        DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("To", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                    case .upcoming:
                        LabeledContent("Period", value: "Next five years")
                    }
                } footer: {
                    Text("Listello skips calendar events that have already been imported. All Upcoming covers every available event from today through the next five years.")
                }

                if !store.projects.isEmpty {
                    Section("Assign Imported Tasks") {
                        Picker("Project", selection: $projectID) {
                            Text("No Project").tag(nil as UUID?)
                            ForEach(store.projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        importEvents()
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                ProgressView()
                            } else {
                                Label("Import Calendar Events", systemImage: "square.and.arrow.down")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isImporting)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ListelloBackground())
            .navigationTitle("Import from Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Calendar Import", isPresented: resultPresented) {
                Button("Done") { dismiss() }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private var resultPresented: Binding<Bool> {
        Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )
    }

    private func importEvents() {
        isImporting = true
        Task {
            let interval = importInterval
            let entries = await calendarService.entries(from: interval.start, to: interval.end, requestAccess: true)
            guard calendarService.hasFullAccess else {
                resultMessage = "Allow full Calendar access in iPhone Settings to import events."
                isImporting = false
                return
            }

            let count = store.importCalendarEntries(entries, projectID: projectID)
            resultMessage = count == 0
                ? "No new calendar events were found in that period."
                : "Imported \(count) calendar \(count == 1 ? "event" : "events") as tasks."
            isImporting = false
        }
    }

    private var importInterval: (start: Date, end: Date) {
        let calendar = Calendar.current
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: selectedDay)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .range:
            let start = calendar.startOfDay(for: rangeStart)
            let finalDay = calendar.startOfDay(for: rangeEnd)
            return (start, calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay)
        case .upcoming:
            let start = Date()
            return (start, calendar.date(byAdding: .year, value: 5, to: start) ?? start)
        }
    }
}
