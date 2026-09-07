import SwiftUI

enum ListelloTutorialL10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Tutorial")
    }
}

enum ListelloTab: Hashable {
    case list
    case schedule
    case settings
}

enum ListelloTutorialTarget: Hashable {
    case quickAdd
    case projectsAndLists
    case sort
    case scheduleAdd
    case replay
}

private struct ListelloTutorialAnchorKey: PreferenceKey {
    static var defaultValue: [ListelloTutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [ListelloTutorialTarget: Anchor<CGRect>],
        nextValue: () -> [ListelloTutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func listelloTutorialTarget(_ target: ListelloTutorialTarget) -> some View {
        anchorPreference(key: ListelloTutorialAnchorKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

private struct ReplayListelloTutorialKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var replayListelloTutorial: () -> Void {
        get { self[ReplayListelloTutorialKey.self] }
        set { self[ReplayListelloTutorialKey.self] = newValue }
    }
}

enum ListelloTutorialStep: Int, CaseIterable {
    case welcome
    case quickAdd
    case projectsAndLists
    case sortAndPick
    case schedule
    case settings

    var title: String {
        switch self {
        case .welcome: L10n.text("Listello")
        case .quickAdd: L10n.text("Add a task")
        case .projectsAndLists: L10n.text("Projects and lists")
        case .sortAndPick: L10n.text("Sort")
        case .schedule: L10n.text("Schedule")
        case .settings: L10n.text("Settings")
        }
    }

    var message: String {
        switch self {
        case .welcome:
            ListelloTutorialL10n.text("A simple, flexible home for tasks, lists and plans.")
        case .quickAdd:
            ListelloTutorialL10n.text("Type here to add a task or item without leaving your list.")
        case .projectsAndLists:
            ListelloTutorialL10n.text("Open the sidebar to create, choose and reorder projects and lists.")
        case .sortAndPick:
            ListelloTutorialL10n.text("Choose how the list is sorted. Random Pick appears beside this when tasks are available.")
        case .schedule:
            ListelloTutorialL10n.text("Add timed tasks or breaks. If something clashes, Listello can shift only the entries that need to move.")
        case .settings:
            ListelloTutorialL10n.text("Change defaults, appearance and archiving here. You can replay this tutorial whenever you like.")
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "sparkles"
        case .quickAdd: "plus.circle.fill"
        case .projectsAndLists: "square.grid.2x2.fill"
        case .sortAndPick: "dice.fill"
        case .schedule: "calendar.badge.clock"
        case .settings: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .listelloViolet
        case .quickAdd: .listelloTeal
        case .projectsAndLists: .listelloCoral
        case .sortAndPick: .listelloViolet
        case .schedule: .listelloSky
        case .settings: .listelloTeal
        }
    }

    var tab: ListelloTab {
        switch self {
        case .welcome, .quickAdd, .projectsAndLists, .sortAndPick: .list
        case .schedule: .schedule
        case .settings: .settings
        }
    }

    var target: ListelloTutorialTarget? {
        switch self {
        case .welcome: nil
        case .quickAdd: .quickAdd
        case .projectsAndLists: .projectsAndLists
        case .sortAndPick: .sort
        case .schedule: .scheduleAdd
        case .settings: .replay
        }
    }
}

struct ListelloTutorialOverlay: View {
    let step: ListelloTutorialStep
    let stepNumber: Int
    let stepCount: Int
    let targetFrame: CGRect?
    let previous: () -> Void
    let next: () -> Void
    let skip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let visibleTarget = targetFrame.flatMap { frame in
                frame.width > 1 && frame.height > 1 ? frame.insetBy(dx: -8, dy: -8) : nil
            }
            let cardAtTop = visibleTarget.map { $0.midY > proxy.size.height * 0.52 } ?? false

            ZStack {
                dimmingLayer(targetFrame: visibleTarget)

                if let visibleTarget {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(step.tint, lineWidth: 3)
                        .frame(width: visibleTarget.width, height: visibleTarget.height)
                        .position(x: visibleTarget.midX, y: visibleTarget.midY)
                        .shadow(color: step.tint.opacity(0.55), radius: 10)
                        .accessibilityHidden(true)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(ListelloTutorialL10n.text("Skip"), action: skip)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.28), in: Capsule())
                    }

                    if cardAtTop {
                        tutorialCard
                        Spacer(minLength: 24)
                    } else {
                        Spacer(minLength: 24)
                        tutorialCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, max(proxy.safeAreaInsets.top + 10, 18))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 72, 86))
            }
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .animation(reduceMotion ? nil : .snappy, value: step)
    }

    private func dimmingLayer(targetFrame: CGRect?) -> some View {
        ZStack {
            Color.black.opacity(0.62)

            if let targetFrame {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .position(x: targetFrame.midX, y: targetFrame.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: step.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(step.tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.title3.weight(.bold))
                    Text("\(stepNumber + 1) / \(stepCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(step.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if stepNumber > 0 {
                    Button(ListelloTutorialL10n.text("Back"), action: previous)
                        .buttonStyle(.bordered)
                }

                Spacer()

                Button(stepNumber == stepCount - 1 ? L10n.text("Done") : ListelloTutorialL10n.text("Next"), action: next)
                    .buttonStyle(.borderedProminent)
                    .tint(step.tint)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    @ViewBuilder
    func listelloTutorialOverlay(
        isPresented: Bool,
        step: ListelloTutorialStep,
        stepNumber: Int,
        previous: @escaping () -> Void,
        next: @escaping () -> Void,
        skip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(ListelloTutorialAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if isPresented {
                    ListelloTutorialOverlay(
                        step: step,
                        stepNumber: stepNumber,
                        stepCount: ListelloTutorialStep.allCases.count,
                        targetFrame: step.target.flatMap { target in
                            anchors[target].map { proxy[$0] }
                        },
                        previous: previous,
                        next: next,
                        skip: skip
                    )
                }
            }
        }
    }
}
