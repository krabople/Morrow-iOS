import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(task.isCompleted ? Color.quietSage : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)

                    if task.isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Important")
                    }
                }

                if let scheduledAt = task.scheduledAt {
                    Label(scheduleLabel(for: scheduledAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(isOverdue(scheduledAt) && !task.isCompleted ? Color.red : Color.secondary)
                }

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func scheduleLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < Date()
    }
}
