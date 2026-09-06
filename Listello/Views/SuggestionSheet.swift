import SwiftUI

struct SuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var task: TaskItem

    let nextSuggestion: (UUID) -> TaskItem?
    let complete: (TaskItem) -> Void

    init(
        task: TaskItem,
        nextSuggestion: @escaping (UUID) -> TaskItem?,
        complete: @escaping (TaskItem) -> Void
    ) {
        _task = State(initialValue: task)
        self.nextSuggestion = nextSuggestion
        self.complete = complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ScrollView {
                    VStack(spacing: 18) {
                        ListelloMark(size: 62)

                        Text("How about this?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(task.title)
                            .font(.title2.bold())
                            .foregroundStyle(Color.listelloInk)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)

                        if !task.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("Notes", systemImage: "note.text")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(task.notes)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }

                        if let duration = task.expectedDurationMinutes {
                            Label(durationLabel(duration), systemImage: "timer")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.listelloSky)
                        } else {
                            Label("No duration estimate", systemImage: "timer")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let scheduledAt = task.scheduledAt {
                            Label(
                                scheduledAt.formatted(.dateTime.weekday(.wide).hour().minute()),
                                systemImage: "clock"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }

                Button {
                    complete(task)
                    dismiss()
                } label: {
                    Label("Mark Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.listelloTeal)
                .controlSize(.large)

                Button("Pick again") {
                    if let next = nextSuggestion(task.id) {
                        withAnimation { task = next }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(ListelloBackground())
            .navigationTitle("Random pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func durationLabel(_ minutes: Int) -> String {
        L10n.duration(minutes)
    }
}
