import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    let openTask: (TaskItem) -> Void
    @State private var mode: PlanMode = .agenda
    @State private var selectedDay = Date()

    enum PlanMode: String, CaseIterable, Identifiable {
        case agenda = "Agenda"
        case calendar = "Calendar"
        case matrix = "Priorities"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: weekRange, title: "Plan your week", subtitle: "Tasks and time, in one realistic view.")

                Picker("Planning view", selection: $mode) {
                    ForEach(PlanMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .agenda: AgendaPlanView(selectedDay: $selectedDay, openTask: openTask)
                case .calendar: MonthPlanView(selectedDay: $selectedDay, openTask: openTask)
                case .matrix: PriorityMatrixView(openTask: openTask)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(MorrowTheme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekRange: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
        return "\(Date.now.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

private struct AgendaPlanView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    let openTask: (TaskItem) -> Void

    private var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) } }
    private var dayTasks: [TaskItem] { model.tasks.filter { task in guard let date = task.dueDate else { return false }; return Calendar.current.isDate(date, inSameDayAs: selectedDay) } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    Button { selectedDay = day } label: {
                        VStack(spacing: 5) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.bold()).opacity(0.65)
                            Text(day.formatted(.dateTime.day())).font(.subheadline.bold())
                            Circle().fill(selected ? MorrowTheme.apricot : MorrowTheme.forest.opacity(0.35)).frame(width: 4, height: 4)
                        }
                        .foregroundStyle(selected ? Color.white : MorrowTheme.secondary)
                        .frame(width: 44, height: 67)
                        .background(selected ? MorrowTheme.forest : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { if !selected { RoundedRectangle(cornerRadius: 14).stroke(MorrowTheme.divider) } }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        CapacityCard(usedMinutes: dayTasks.reduce(0) { $0 + $1.durationMinutes }, capacityMinutes: 300)

        HStack {
            SectionTitle(title: "Timeline")
            Button("Auto-schedule") { model.autoSchedule(on: selectedDay) }
                .font(.caption.bold())
                .foregroundStyle(MorrowTheme.forest)
        }

        VStack(spacing: 11) {
            if dayTasks.isEmpty {
                ContentUnavailableView("An open day", systemImage: "calendar.badge.plus", description: Text("Add a task or enjoy the breathing room."))
                    .frame(minHeight: 210)
                    .morrowCard()
            } else {
                ForEach(dayTasks) { task in
                    Button { openTask(task) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(task.dueDate?.formatted(date: .omitted, time: .shortened) ?? "Any")
                                .font(.caption2.bold())
                                .foregroundStyle(MorrowTheme.secondary)
                                .frame(width: 47, alignment: .leading)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.subheadline.bold()).foregroundStyle(MorrowTheme.ink)
                                Text("\(task.durationMinutes) min · \(task.project)").font(.caption).foregroundStyle(MorrowTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal").foregroundStyle(MorrowTheme.secondary.opacity(0.45))
                        }
                        .padding(15)
                        .background(color(for: task).opacity(0.15), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func color(for task: TaskItem) -> Color {
        task.project == "Northstar" ? MorrowTheme.violet : task.project == "Personal" ? MorrowTheme.apricot : MorrowTheme.forest
    }
}

private struct MonthPlanView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    let openTask: (TaskItem) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(Date.now.formatted(.dateTime.month(.wide).year())).font(.headline.bold()); Spacer(); Button { selectedDay = Date() } label: { Text("Today").font(.caption.bold()) } }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in Text(label).font(.caption2.bold()).foregroundStyle(MorrowTheme.secondary).frame(height: 22) }
                ForEach(1...35, id: \.self) { day in
                    let isToday = day == Calendar.current.component(.day, from: Date())
                    let task = model.tasks.first { item in item.dueDate.map { Calendar.current.component(.day, from: $0) == day } ?? false }
                    Button {
                        if let task { openTask(task) }
                    } label: {
                        VStack(spacing: 5) {
                            Text("\(day)").font(.caption.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? Color.white : MorrowTheme.ink)
                                .frame(width: 27, height: 27)
                                .background(isToday ? MorrowTheme.forest : .clear, in: Circle())
                            Circle().fill(task == nil ? .clear : MorrowTheme.violet).frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .morrowCard()

        VStack(spacing: 12) {
            SectionTitle(title: "Next up", count: model.openTasks.count)
            TaskListCard(tasks: Array(model.openTasks.prefix(5)), onOpen: openTask)
        }
    }
}

private struct PriorityMatrixView: View {
    @Environment(AppModel.self) private var model
    let openTask: (TaskItem) -> Void
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 11) {
            MatrixQuadrant(title: "Do now", detail: "Urgent + important", tint: Color(red: 0.64, green: 0.31, blue: 0.26), tasks: model.openTasks.filter { $0.priority == .urgent }, openTask: openTask)
            MatrixQuadrant(title: "Schedule", detail: "Important, not urgent", tint: MorrowTheme.violet, tasks: model.openTasks.filter { $0.priority == .important }, openTask: openTask)
            MatrixQuadrant(title: "Delegate", detail: "Urgent, less important", tint: MorrowTheme.forest, tasks: model.openTasks.filter { $0.priority == .normal }, openTask: openTask)
            MatrixQuadrant(title: "Let go", detail: "Neither", tint: MorrowTheme.secondary, tasks: model.openTasks.filter { $0.priority == .low }, openTask: openTask)
        }
    }
}

private struct MatrixQuadrant: View {
    let title: String
    let detail: String
    let tint: Color
    let tasks: [TaskItem]
    let openTask: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.bold()).foregroundStyle(tint)
            Text(detail).font(.caption2).foregroundStyle(MorrowTheme.secondary)
            Divider()
            ForEach(tasks.prefix(3)) { task in
                Button { openTask(task) } label: {
                    Text(task.title).font(.caption.weight(.semibold)).foregroundStyle(MorrowTheme.ink).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(9).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 185, alignment: .topLeading)
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.16)) }
    }
}
