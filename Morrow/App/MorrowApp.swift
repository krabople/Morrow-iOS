import SwiftUI

@main
struct MorrowApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(nil)
        }
    }
}

