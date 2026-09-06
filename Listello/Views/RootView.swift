import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: TaskStore

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

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.applyAutomaticArchiving() }
        }
    }
}
