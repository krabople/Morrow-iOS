import SwiftUI

@main
struct ListelloApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var calendarService = CalendarService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calendarService)
                .tint(.listelloTeal)
        }
    }
}
