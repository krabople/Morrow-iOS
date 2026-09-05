import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private let features = [
        FeatureLink(title: "Lists & spaces", detail: "4 spaces", symbol: "folder.fill", tint: MorrowTheme.violet, kind: .lists),
        FeatureLink(title: "Habits", detail: "4 today", symbol: "repeat", tint: Color(red: 0.25, green: 0.53, blue: 0.40), kind: .habits),
        FeatureLink(title: "Goals", detail: "3 active", symbol: "target", tint: MorrowTheme.violet, kind: .goals),
        FeatureLink(title: "Insights", detail: "72% rhythm", symbol: "chart.xyaxis.line", tint: Color(red: 0.76, green: 0.42, blue: 0.23), kind: .insights),
        FeatureLink(title: "Notes", detail: "18 notes", symbol: "doc.text.fill", tint: Color(red: 0.28, green: 0.48, blue: 0.59), kind: .notes),
        FeatureLink(title: "Routines", detail: "AM + PM", symbol: "sun.horizon.fill", tint: Color(red: 0.55, green: 0.43, blue: 0.24), kind: .routines),
        FeatureLink(title: "Templates", detail: "8 saved", symbol: "square.stack.3d.up.fill", tint: MorrowTheme.secondary, kind: .templates),
        FeatureLink(title: "Automations", detail: "6 running", symbol: "wand.and.sparkles", tint: Color(red: 0.58, green: 0.34, blue: 0.47), kind: .automations),
        FeatureLink(title: "People", detail: "12 shared", symbol: "person.2.fill", tint: Color(red: 0.65, green: 0.38, blue: 0.31), kind: .people),
        FeatureLink(title: "Archive", detail: "342 done", symbol: "archivebox.fill", tint: MorrowTheme.forest, kind: .archive),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Your whole system", title: "More", subtitle: "Power tools that stay out of the way until needed.")

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(features) { item in
                        NavigationLink(value: item) {
                            FeatureTile(title: item.title, detail: item.detail, symbol: item.symbol, tint: item.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 12) {
                    SectionTitle(title: "Settings")
                    NavigationLink(value: FeatureLink(title: "Settings", detail: "Appearance, alerts and privacy", symbol: "gearshape.fill", tint: MorrowTheme.forest, kind: .settings)) {
                        HStack(spacing: 13) {
                            Image(systemName: "gearshape.fill").foregroundStyle(MorrowTheme.forest).frame(width: 38, height: 38).background(MorrowTheme.forestSoft, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) { Text("Settings").font(.subheadline.bold()); Text("Appearance, alerts and privacy").font(.caption).foregroundStyle(MorrowTheme.secondary) }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(MorrowTheme.secondary)
                        }
                        .morrowCard()
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "command").foregroundStyle(MorrowTheme.forest).frame(width: 38, height: 38).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Connected, not complicated").font(.subheadline.bold())
                        Text("Calendar, email, Siri, Shortcuts, widgets and Apple Watch can all feed one trusted inbox.").font(.caption).foregroundStyle(MorrowTheme.secondary)
                    }
                }
                .padding(16)
                .background(MorrowTheme.forestSoft, in: RoundedRectangle(cornerRadius: 21))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(MorrowTheme.background)
        .navigationDestination(for: FeatureLink.self) { FeatureDetailView(feature: $0) }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureLink: Identifiable, Hashable {
    enum Kind: String, Hashable { case lists, habits, goals, insights, notes, routines, templates, automations, people, archive, settings }
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let kind: Kind

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind }
    func hash(into hasher: inout Hasher) { hasher.combine(kind) }
}

private struct FeatureDetailView: View {
    @Environment(AppModel.self) private var model
    let feature: FeatureLink
    @State private var morningPlan = true
    @State private var smartReminders = true
    @State private var locationAwareness = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: feature.symbol).font(.title3).foregroundStyle(feature.tint).frame(width: 50, height: 50).background(feature.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) { Text(feature.title).font(.title2.bold()); Text(feature.detail).font(.subheadline).foregroundStyle(MorrowTheme.secondary) }
                }

                switch feature.kind {
                case .habits: habits
                case .lists: lists
                case .goals: goals
                case .insights: insights
                case .automations: automations
                case .settings: settings
                default: generic
                }
            }
            .padding(18)
        }
        .background(MorrowTheme.background)
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var habits: some View {
        VStack(spacing: 11) {
            ForEach(model.habits) { habit in
                Button { model.incrementHabit(habit.id) } label: {
                    HStack(spacing: 13) {
                        Image(systemName: habit.symbol).foregroundStyle(feature.tint).frame(width: 36, height: 36).background(feature.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) { Text(habit.title).font(.subheadline.bold()); Text("\(habit.progress) of \(habit.target) \(habit.unit) · \(habit.streak)-day streak").font(.caption).foregroundStyle(MorrowTheme.secondary) }
                        Spacer(); Image(systemName: habit.isComplete ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(habit.isComplete ? feature.tint : MorrowTheme.secondary)
                    }.morrowCard()
                }.buttonStyle(.plain)
            }
        }
    }

    private var lists: some View {
        VStack(spacing: 11) {
            ForEach([("Northstar", "Product launch and big-picture work", "purple"), ("Personal", "Home, admin and things for me", "orange"), ("People", "Promises, replies and shared plans", "green"), ("Wellbeing", "Health, habits and proper rest", "blue")], id: \.0) { item in
                HStack(spacing: 13) { Image(systemName: "folder.fill").foregroundStyle(feature.tint); VStack(alignment: .leading) { Text(item.0).font(.subheadline.bold()); Text(item.1).font(.caption).foregroundStyle(MorrowTheme.secondary) }; Spacer(); Text("\(model.openTasks.filter { $0.project == item.0 }.count)").font(.caption.bold()).foregroundStyle(MorrowTheme.secondary) }.morrowCard()
            }
        }
    }

    private var goals: some View {
        VStack(spacing: 11) {
            GoalCard(title: "Launch Northstar", detail: "3 of 5 milestones", progress: 0.6, tint: MorrowTheme.violet)
            GoalCard(title: "Feel stronger", detail: "18 of 30 sessions", progress: 0.6, tint: MorrowTheme.forest)
            GoalCard(title: "Read 24 books", detail: "16 of 24 books", progress: 0.67, tint: Color(red: 0.72, green: 0.42, blue: 0.24))
        }
    }

    private var insights: some View {
        VStack(spacing: 14) {
            HStack { insightNumber("72%", "Weekly rhythm"); Divider(); insightNumber("14", "Tasks finished"); Divider(); insightNumber("4h", "Focus time") }.morrowCard()
            VStack(alignment: .leading, spacing: 14) { Text("Your best focus window").font(.headline); Text("You finish deep-work tasks most reliably between 9:00 and 11:00 AM.").font(.subheadline).foregroundStyle(MorrowTheme.secondary); HStack(alignment: .bottom, spacing: 7) { ForEach([0.35, 0.5, 0.82, 0.65, 0.9, 0.42, 0.28], id: \.self) { value in Capsule().fill(feature.tint.opacity(0.75)).frame(height: 90 * value) } }.frame(maxWidth: .infinity, minHeight: 90, alignment: .bottom) }.morrowCard()
        }
    }

    private var automations: some View {
        VStack(spacing: 0) {
            settingRow("Morning plan", "Suggest a realistic day at 8:00 AM", "sun.max.fill", isOn: $morningPlan)
            Divider().padding(.leading, 52)
            settingRow("Smart reminders", "Nudge only while there is time to act", "bell.badge.fill", isOn: $smartReminders)
            Divider().padding(.leading, 52)
            settingRow("Location awareness", "Surface errands when you are nearby", "location.fill", isOn: $locationAwareness)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(MorrowTheme.divider) }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            settingRow("Daily planning prompt", "A gentle morning reset", "sun.horizon", isOn: $morningPlan)
            Divider().padding(.leading, 52)
            settingRow("Adaptive reminders", "Fewer, better-timed alerts", "bell", isOn: $smartReminders)
            Divider().padding(.leading, 52)
            settingRow("Private on this device", "Your tasks stay in local storage", "lock.fill", isOn: .constant(true))
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(MorrowTheme.divider) }
    }

    private var generic: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Everything in one calm place").font(.headline)
            Text(genericDescription).font(.subheadline).foregroundStyle(MorrowTheme.secondary)
        }.morrowCard()
    }

    private var genericDescription: String {
        switch feature.kind {
        case .notes: "Capture reference material beside the work it supports, then find it through universal search."
        case .routines: "Build reusable morning, evening and weekly reset sequences without cluttering your task lists."
        case .templates: "Save projects and checklists you repeat, from travel packing to meeting preparation."
        case .people: "Share lists, assign tasks, leave comments and keep promises visible in one place."
        case .archive: "Review completed work, restore tasks and export a clean record whenever you need it."
        default: "A focused space for this part of your system."
        }
    }

    private func insightNumber(_ value: String, _ label: String) -> some View { VStack(spacing: 4) { Text(value).font(.title3.bold()); Text(label).font(.caption2).foregroundStyle(MorrowTheme.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity) }
    private func settingRow(_ title: String, _ detail: String, _ symbol: String, isOn: Binding<Bool>) -> some View { HStack(spacing: 13) { Image(systemName: symbol).foregroundStyle(feature.tint).frame(width: 36, height: 36).background(feature.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()); Text(detail).font(.caption).foregroundStyle(MorrowTheme.secondary) }; Spacer(); Toggle("", isOn: isOn).labelsHidden().tint(MorrowTheme.forest) }.padding(15) }
}

private struct GoalCard: View {
    let title: String; let detail: String; let progress: Double; let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 12) { HStack { Text(title).font(.subheadline.bold()); Spacer(); Text("\(Int(progress * 100))%").font(.caption.bold()).foregroundStyle(tint) }; ProgressView(value: progress).tint(tint); Text(detail).font(.caption).foregroundStyle(MorrowTheme.secondary) }.morrowCard() }
}
