import SwiftUI

struct DurationOptionsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var customMinutes = ""

    private let suggestedOptions = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 240]

    var body: some View {
        Form {
            Section {
                ForEach(suggestedOptions, id: \.self) { minutes in
                    Button {
                        toggle(minutes)
                    } label: {
                        HStack {
                            Text(durationLabel(minutes))
                                .foregroundStyle(Color.listelloInk)
                            Spacer()
                            Image(systemName: isSelected(minutes) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected(minutes) ? Color.listelloTeal : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected(minutes) && store.preferences.durationOptions.count == 1)
                }
            } header: {
                Text("Suggested Choices")
            } footer: {
                Text("Tap to choose which durations appear when editing a task. “No estimate” always remains available.")
            }

            Section("Add Another Duration") {
                HStack {
                    TextField("Minutes", text: $customMinutes)
                        .keyboardType(.numberPad)
                    Button("Add") { addCustomDuration() }
                        .fontWeight(.semibold)
                        .disabled(customValue == nil || customValue.map { isSelected($0) } == true)
                }

                ForEach(customOptions, id: \.self) { minutes in
                    HStack {
                        Text(durationLabel(minutes))
                        Spacer()
                        Button(role: .destructive) {
                            remove(minutes)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(store.preferences.durationOptions.count == 1)
                        .accessibilityLabel(L10n.format("remove_duration", durationLabel(minutes)))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ListelloBackground())
        .navigationTitle("Duration Choices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customValue: Int? {
        guard let value = Int(customMinutes), (1...1_440).contains(value) else { return nil }
        return value
    }

    private var customOptions: [Int] {
        store.preferences.durationOptions.filter { !suggestedOptions.contains($0) }
    }

    private func isSelected(_ minutes: Int) -> Bool {
        store.preferences.durationOptions.contains(minutes)
    }

    private func toggle(_ minutes: Int) {
        if isSelected(minutes) {
            remove(minutes)
        } else {
            store.setDurationOptions(store.preferences.durationOptions + [minutes])
        }
    }

    private func remove(_ minutes: Int) {
        store.setDurationOptions(store.preferences.durationOptions.filter { $0 != minutes })
    }

    private func addCustomDuration() {
        guard let value = customValue else { return }
        store.setDurationOptions(store.preferences.durationOptions + [value])
        customMinutes = ""
    }

    private func durationLabel(_ minutes: Int) -> String {
        L10n.duration(minutes)
    }
}
