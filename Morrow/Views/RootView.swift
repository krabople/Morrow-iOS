import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddTask = false
    @State private var showingPicker = false
    @State private var selectedTask: TaskItem?
    @State private var showingSearch = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                TodayView(
                    showAddTask: { showingAddTask = true },
                    showPicker: { showingPicker = true },
                    openTask: { selectedTask = $0 }
                )
                .toolbar { commonToolbar }
            }
            .tag(AppTab.today)
            .tabItem { Label("Today", systemImage: "sparkles") }

            NavigationStack {
                InboxView(openTask: { selectedTask = $0 })
                    .toolbar { commonToolbar }
            }
            .tag(AppTab.inbox)
            .tabItem { Label("Inbox", systemImage: "tray") }

            NavigationStack {
                PlanView(openTask: { selectedTask = $0 })
                    .toolbar { commonToolbar }
            }
            .tag(AppTab.plan)
            .tabItem { Label("Plan", systemImage: "calendar") }

            NavigationStack {
                FocusView(openTask: { selectedTask = $0 })
                    .toolbar { commonToolbar }
            }
            .tag(AppTab.focus)
            .tabItem { Label("Focus", systemImage: "scope") }

            NavigationStack {
                MoreView()
                    .toolbar { commonToolbar }
            }
            .tag(AppTab.more)
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(MorrowTheme.forest)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .sheet(isPresented: $showingAddTask) {
            AddTaskView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPicker) {
            RandomPickerView()
                .presentationDetents([.fraction(0.68), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSearch) {
            SearchView(openTask: { task in
                showingSearch = false
                selectedTask = task
            })
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(taskID: task.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(MorrowTheme.forest, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("Morrow")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MorrowTheme.ink)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Search")
            Button { showingAddTask = true } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("Add task")
        }
    }
}
