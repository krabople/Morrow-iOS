import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TaskListView()
                .tabItem {
                    Label("List", systemImage: "checklist")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
        }
    }
}
