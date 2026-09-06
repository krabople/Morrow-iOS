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
            VStack(spacing: 22) {
                Spacer()

                ListelloMark(size: 62)

                Text("How about this?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(task.title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.listelloInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let scheduledAt = task.scheduledAt {
                    Label(
                        scheduledAt.formatted(.dateTime.weekday(.wide).hour().minute()),
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

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

                Button("Pick Another") {
                    if let next = nextSuggestion(task.id) {
                        withAnimation { task = next }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(ListelloBackground())
            .navigationTitle("Pick One")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
