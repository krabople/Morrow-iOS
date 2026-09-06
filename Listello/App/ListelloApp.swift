import SwiftUI

@main
struct ListelloApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var remindersService = RemindersService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calendarService)
                .environmentObject(remindersService)
                .tint(.listelloTeal)
                .preferredColorScheme(store.preferences.appearance.colorScheme)
        }
    }
}
