import SwiftUI

extension Color {
    static let quietSage = Color(red: 0.47, green: 0.59, blue: 0.49)
    static let quietInk = Color(red: 0.13, green: 0.14, blue: 0.15)
    static let quietCream = Color(red: 0.98, green: 0.97, blue: 0.93)
}

struct QuietCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

extension View {
    func quietCard() -> some View {
        modifier(QuietCardModifier())
    }
}
