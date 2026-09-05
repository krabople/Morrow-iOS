import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model
    let openTask: (TaskItem) -> Void
    @State private var filter: InboxFilter = .all
    @State private var searchText = ""

    enum InboxFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplanned = "Unplanned"
        case flagged = "Flagged"
        case waiting = "Waiting"
        var id: String { rawValue }
    }

    private var filteredTasks: [TaskItem] {
        model.inboxTasks.filter { task in
            let matchesSearch = searchText.isEmpty || "\(task.title) \(task.project) \(task.tags.joined(separator: " "))".localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .unplanned: matchesFilter = task.dueDate == nil
            case .flagged: matchesFilter = task.isFlagged
            case .waiting: matchesFilter = task.isWaiting
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "Capture now, decide later", title: "Inbox", subtitle: "Every loose end, ready when you are.")

                HStack(spacing: 9) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color(red: 0.58, green: 0.32, blue: 0.19))
                        .frame(width: 36, height: 36)
                        .background(MorrowTheme.apricotSoft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Three tasks need a decision").font(.subheadline.bold())
                        Text("Date them, delegate them, or move them to Someday.").font(.caption).foregroundStyle(MorrowTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(MorrowTheme.secondary)
                }
                .morrowCard()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(InboxFilter.allCases) { item in
                            Button(item.rawValue) { filter = item }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(filter == item ? Color.white : MorrowTheme.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(filter == item ? MorrowTheme.forest : Color.white, in: Capsule())
                                .overlay { if filter != item { Capsule().stroke(MorrowTheme.divider) } }
                        }
                    }
                }

                VStack(spacing: 12) {
                    SectionTitle(title: "Captured", count: filteredTasks.count)
                    TaskListCard(tasks: filteredTasks, onOpen: openTask)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(MorrowTheme.background)
        .searchable(text: $searchText, prompt: "Tasks, projects and tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}
