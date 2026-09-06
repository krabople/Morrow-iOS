import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let project: ProjectItem?
    var showsScheduleLabel = true
    let onToggle: () -> Void

    private var accent: Color {
        project?.color.tint ?? (task.isImportant ? .listelloAmber : .listelloTeal)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(task.isCompleted ? accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? Color.secondary : Color.listelloInk)

                    if task.isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.listelloAmber)
                            .accessibilityLabel("Important")
                    }
                }

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let project {
                        Label(project.name, systemImage: "folder.fill")
                            .foregroundStyle(project.color.tint)
                    }

                    if let duration = task.expectedDurationMinutes {
                        Label(durationLabel(duration), systemImage: "timer")
                            .foregroundStyle(Color.listelloSky)
                    }

                    if task.calendarEventIdentifier != nil {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(Color.listelloViolet)
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

                if showsScheduleLabel, let scheduledAt = task.scheduledAt {
                    Label(scheduleLabel(for: scheduledAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(isOverdue(scheduledAt) && !task.isCompleted ? Color.red : Color.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(accent.opacity(0.095), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 12)
        }
        .contentShape(Rectangle())
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
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
