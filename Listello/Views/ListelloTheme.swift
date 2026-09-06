import SwiftUI
import UIKit

extension Color {
    static let listelloTeal = Color(red: 0.13, green: 0.70, blue: 0.66)
    static let listelloSky = Color(red: 0.25, green: 0.63, blue: 0.93)
    static let listelloAmber = Color(red: 1.00, green: 0.67, blue: 0.19)
    static let listelloCoral = Color(red: 0.98, green: 0.39, blue: 0.34)
    static let listelloViolet = Color(red: 0.51, green: 0.42, blue: 0.86)
    static let listelloRose = Color(red: 0.91, green: 0.37, blue: 0.60)
    static let listelloInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
            : UIColor(red: 0.08, green: 0.13, blue: 0.22, alpha: 1)
    })
    static let listelloCream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.055, blue: 0.09, alpha: 1)
            : UIColor(red: 1.00, green: 0.98, blue: 0.93, alpha: 1)
    })

    init(hex: String) {
        let value = Int(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x38BDB2
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension ProjectColor {
    var tint: Color {
        switch self {
        case .teal: .listelloTeal
        case .sky: .listelloSky
        case .blue: Color(red: 0.12, green: 0.42, blue: 0.92)
        case .indigo: Color(red: 0.28, green: 0.31, blue: 0.78)
        case .amber: .listelloAmber
        case .coral: .listelloCoral
        case .violet: .listelloViolet
        case .purple: Color(red: 0.64, green: 0.32, blue: 0.82)
        case .rose: .listelloRose
        case .red: Color(red: 0.88, green: 0.22, blue: 0.26)
        case .orange: Color(red: 0.96, green: 0.48, blue: 0.14)
        case .green: Color(red: 0.20, green: 0.66, blue: 0.33)
        case .mint: Color(red: 0.16, green: 0.75, blue: 0.55)
        case .slate: Color(red: 0.38, green: 0.45, blue: 0.56)
        }
    }
}

struct ListelloMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            segment(color: .listelloTeal, from: 0.03, to: 0.27)
            segment(color: .listelloSky, from: 0.28, to: 0.50)
            segment(color: .listelloAmber, from: 0.51, to: 0.71)
            segment(color: .listelloCoral, from: 0.72, to: 0.88)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.listelloInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func segment(color: Color, from: CGFloat, to: CGFloat) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round))
            .rotationEffect(.degrees(-45))
    }
}

struct ListelloHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ListelloMark(size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.listelloInk)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: Color.listelloSky.opacity(0.12), radius: 18, y: 8)
    }
}

struct ListelloBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.listelloCream,
                Color.listelloSky.opacity(0.10),
                Color.listelloTeal.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
