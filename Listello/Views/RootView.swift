import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TaskListView()
                .tabItem {
                    Label("List", systemImage: "checklist.checked")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}
