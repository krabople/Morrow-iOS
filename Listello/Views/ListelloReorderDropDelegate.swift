import SwiftUI

struct ListelloReorderFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct ListelloReorderHandle: View {
    let coordinateSpace: String
    let isDragging: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(isDragging ? Color.listelloTeal : Color.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(isDragging ? 1.08 : 1)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpace))
                    .onChanged { onChanged($0.location) }
                    .onEnded { _ in onEnded() }
            )
            .accessibilityLabel("Reorder")
            .accessibilityHint("Drag up or down to change the order")
    }
}

func nearestReorderTarget(
    to location: CGPoint,
    frames: [UUID: CGRect],
    allowedIDs: Set<UUID>
) -> UUID? {
    frames
        .filter { allowedIDs.contains($0.key) }
        .min { lhs, rhs in
            abs(lhs.value.midY - location.y) < abs(rhs.value.midY - location.y)
        }?
        .key
}

struct ListelloReorderFrame: ViewModifier {
    let id: UUID
    let coordinateSpace: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ListelloReorderFramesKey.self,
                    value: [id: proxy.frame(in: .named(coordinateSpace))]
                )
            }
        }
    }
}

extension View {
    func listelloReorderFrame(id: UUID, in coordinateSpace: String) -> some View {
        modifier(ListelloReorderFrame(id: id, coordinateSpace: coordinateSpace))
    }
}

