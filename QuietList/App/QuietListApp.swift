import SwiftUI

@main
struct QuietListApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.quietSage)
        }
    }
}
