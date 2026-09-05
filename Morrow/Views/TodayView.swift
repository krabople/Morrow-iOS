import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let showAddTask: () -> Void
    let showPicker: () -> Void
    let openTask: (TaskItem) -> Void
    @State private var quickTask = ""

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning."
        case 12..<18: "Good afternoon."
        default: "Good evening."
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    title: greeting,
                    subtitle: "Keep it light. Morrow will help you choose what matters.",
                    actionTitle: "Pick for me",
                    actionSymbol: "shuffle",
                    action: showPicker
                )

                CapacityCard(usedMinutes: model.todayMinutes, capacityMinutes: 210)

                HStack(spacing: 11) {
                    Image(systemName: "plus").foregroundStyle(MorrowTheme.forest)
                    TextField("Add a task — try ‘Call Jo tomorrow’", text: $quickTask)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(addQuickTask)
                    Button(action: addQuickTask) {
                        Image(systemName: "arrow.up")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(MorrowTheme.forest, in: Circle())
                    }
                    .disabled(quickTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .morrowCard(padding: 14)

                VStack(spacing: 12) {
                    SectionTitle(title: "Today’s focus", count: model.todayTasks.filter { !$0.isComplete }.count, actionTitle: "Add", action: showAddTask)
                    TaskListCard(tasks: model.todayTasks, onOpen: openTask)
                }

                HStack(spacing: 12) {
                    ActionCard(title: "Focus sprint", detail: "25 min · Quiet mode", symbol: "timer", tint: MorrowTheme.violet) {
                        model.selectedTab = .focus
                    }
                    ActionCard(title: "Plan tomorrow", detail: "A calm 3-minute reset", symbol: "checklist", tint: MorrowTheme.forest) {
                        model.selectedTab = .plan
                    }
                }

                HabitStrip()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(MorrowTheme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addQuickTask() {
        model.quickAdd(quickTask)
        quickTask = ""
    }
}

private struct ActionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 39, height: 39)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(title).font(.subheadline.bold()).foregroundStyle(MorrowTheme.ink)
                Text(detail).font(.caption2).foregroundStyle(MorrowTheme.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .morrowCard(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

private struct HabitStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAILY RHYTHM")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Small habits, quietly adding up.")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                ForEach(model.habits) { habit in
                    Button { model.incrementHabit(habit.id) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Image(systemName: habit.symbol).font(.caption)
                            Text(habit.title).font(.caption2).lineLimit(1)
                            Text(habit.isComplete ? "Done" : "\(habit.progress)/\(habit.target)")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(habit.isComplete ? MorrowTheme.ink : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(habit.isComplete ? MorrowTheme.apricot : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(MorrowTheme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

