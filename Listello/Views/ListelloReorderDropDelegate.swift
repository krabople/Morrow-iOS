import SwiftUI

struct ListelloDraggableModifier: ViewModifier {
    let identifier: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(identifier)
        } else {
            content
        }
    }
}

extension View {
    func listelloDraggable(_ identifier: String, isEnabled: Bool = true) -> some View {
        modifier(ListelloDraggableModifier(identifier: identifier, isEnabled: isEnabled))
    }
}
