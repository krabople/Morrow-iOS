import SwiftUI

enum MorrowTheme {
    static let background = Color(red: 0.984, green: 0.980, blue: 0.965)
    static let canvas = Color(red: 0.953, green: 0.945, blue: 0.922)
    static let forest = Color(red: 0.145, green: 0.235, blue: 0.208)
    static let forestSoft = Color(red: 0.875, green: 0.925, blue: 0.898)
    static let ink = Color(red: 0.141, green: 0.192, blue: 0.176)
    static let secondary = Color(red: 0.47, green: 0.50, blue: 0.47)
    static let apricot = Color(red: 0.945, green: 0.745, blue: 0.612)
    static let apricotSoft = Color(red: 0.965, green: 0.894, blue: 0.847)
    static let violet = Color(red: 0.42, green: 0.40, blue: 0.78)
    static let violetSoft = Color(red: 0.90, green: 0.89, blue: 0.97)
    static let blueSoft = Color(red: 0.88, green: 0.93, blue: 0.95)
    static let divider = Color(red: 0.90, green: 0.89, blue: 0.85)
}

extension View {
    func morrowCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MorrowTheme.divider, lineWidth: 1)
            }
    }
}

struct MorrowButtonStyle: ButtonStyle {
    var tint = MorrowTheme.forest

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.54, green: 0.29, blue: 0.18))
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .background(MorrowTheme.apricotSoft.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
    }
}

