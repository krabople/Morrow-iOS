import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: TaskStore
    @AppStorage("hasCompletedListelloTutorial") private var hasCompletedTutorial = false

    @State private var selectedTab: ListelloTab = .list
    @State private var tutorialStepNumber = 0
    @State private var showsTutorial = false
    @State private var hasCheckedTutorialState = false

    private let tutorialSteps = ListelloTutorialStep.allCases

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskListView()
                .tabItem {
                    Label("List", systemImage: "checklist.checked")
                }
                .tag(ListelloTab.list)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(ListelloTab.schedule)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(ListelloTab.settings)
        }
        .environment(\.replayListelloTutorial, startTutorial)
        .accessibilityHidden(showsTutorial)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .listelloTutorialOverlay(
            isPresented: showsTutorial,
            step: tutorialSteps[tutorialStepNumber],
            stepNumber: tutorialStepNumber,
            previous: showPreviousTutorialStep,
            next: showNextTutorialStep,
            skip: completeTutorial
        )
        .onAppear(perform: checkTutorialState)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.applyAutomaticArchiving() }
        }
    }

    private func checkTutorialState() {
        guard !hasCheckedTutorialState else { return }
        hasCheckedTutorialState = true

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--listello-tutorial-ui-test") {
            hasCompletedTutorial = false
            startTutorial()
        } else if arguments.contains("--listello-reordering-ui-test") {
            // Keep the tutorial out of this test's later persistence relaunch too.
            hasCompletedTutorial = true
        } else if !hasCompletedTutorial {
            startTutorial()
        }
    }

    private func startTutorial() {
        tutorialStepNumber = 0
        selectedTab = tutorialSteps[0].tab
        withAnimation(.easeInOut(duration: 0.2)) {
            showsTutorial = true
        }
    }

    private func showPreviousTutorialStep() {
        guard tutorialStepNumber > 0 else { return }
        showTutorialStep(tutorialStepNumber - 1)
    }

    private func showNextTutorialStep() {
        guard tutorialStepNumber < tutorialSteps.count - 1 else {
            completeTutorial()
            return
        }
        showTutorialStep(tutorialStepNumber + 1)
    }

    private func showTutorialStep(_ number: Int) {
        withAnimation(.snappy) {
            tutorialStepNumber = number
            selectedTab = tutorialSteps[number].tab
        }
    }

    private func completeTutorial() {
        hasCompletedTutorial = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showsTutorial = false
            selectedTab = .list
        }
    }
}
