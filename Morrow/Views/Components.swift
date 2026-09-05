import SwiftUI

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var actionSymbol = "plus"
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MorrowTheme.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(MorrowTheme.ink)
                Spacer(minLength: 8)
                if let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionSymbol)
                    }
                    .buttonStyle(SoftButtonStyle())
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(actionTitle)
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(MorrowTheme.secondary)
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    var onOpen: () -> Void

    var projectColor: Color {
        switch task.project {
        case "Northstar": MorrowTheme.violet
        case "Personal": Color(red: 0.84, green: 0.45, blue: 0.28)
        case "People": Color(red: 0.28, green: 0.56, blue: 0.43)
        case "Wellbeing": Color(red: 0.31, green: 0.53, blue: 0.62)
        case "Admin": Color(red: 0.61, green: 0.38, blue: 0.44)
        default: MorrowTheme.secondary
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                Button {
                    model.toggle(task.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(task.isComplete ? projectColor : .clear)
                            .overlay {
                                Circle()
                                    .stroke(task.isComplete ? projectColor : Color.gray.opacity(0.35), lineWidth: 2)
                            }
                            .frame(width: 24, height: 24)
                        if task.isComplete {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isComplete ? "Mark incomplete" : "Mark complete")

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(task.isComplete ? MorrowTheme.secondary : MorrowTheme.ink)
                        .strikethrough(task.isComplete)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label(task.dueText, systemImage: "clock")
                        Text("·")
                        Circle().fill(projectColor).frame(width: 6, height: 6)
                        Text(task.project)
                        if task.isFlagged {
                            Image(systemName: "flag.fill").foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.28))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(MorrowTheme.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.gray.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
    }
}

struct SectionTitle: View {
    let title: String
    var count: Int?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(MorrowTheme.ink)
            if let count {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(MorrowTheme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MorrowTheme.canvas, in: Capsule())
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MorrowTheme.forest)
            }
        }
    }
}

struct TaskListCard: View {
    let tasks: [TaskItem]
    let onOpen: (TaskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if tasks.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("There is nothing waiting here."))
                    .frame(minHeight: 180)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task) { onOpen(task) }
                    if index < tasks.count - 1 { Divider().padding(.leading, 52) }
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MorrowTheme.divider) }
    }
}

struct CapacityCard: View {
    let usedMinutes: Int
    let capacityMinutes: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Today’s capacity").font(.caption.weight(.bold))
                Spacer()
                Text("\(usedMinutes / 60)h \(usedMinutes % 60)m of \(capacityMinutes / 60)h \(capacityMinutes % 60)m")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorrowTheme.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MorrowTheme.canvas)
                    Capsule()
                        .fill(usedMinutes > capacityMinutes ? Color.red.opacity(0.7) : MorrowTheme.forest)
                        .frame(width: proxy.size.width * min(1, CGFloat(usedMinutes) / CGFloat(capacityMinutes)))
                }
            }
            .frame(height: 8)
            HStack {
                Label(usedMinutes > capacityMinutes ? "Over capacity" : "Comfortable", systemImage: usedMinutes > capacityMinutes ? "exclamationmark.triangle" : "leaf")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(usedMinutes > capacityMinutes ? .red : MorrowTheme.forest)
                Spacer()
                Text("Includes space for breaks").font(.caption).foregroundStyle(MorrowTheme.secondary)
            }
        }
        .morrowCard()
    }
}

struct FeatureTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Spacer(minLength: 0)
            Text(title).font(.subheadline.bold()).foregroundStyle(MorrowTheme.ink)
            Text(detail).font(.caption).foregroundStyle(MorrowTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .morrowCard(padding: 14)
    }
}
