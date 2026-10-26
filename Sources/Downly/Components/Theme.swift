import AppKit
import DownlyCore
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let indigo = Color(hex: 0x5B4CF2)
    static let violet = Color(hex: 0xA44EF0)
    static let pink = Color(hex: 0xF0559E)
    static let peach = Color(hex: 0xFF8F5E)
    static let accent = Color(hex: 0x8B5CF6)

    static let brand = LinearGradient(colors: [indigo, violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandHorizontal = LinearGradient(colors: [indigo, violet, pink], startPoint: .leading, endPoint: .trailing)
    static let sunrise = LinearGradient(colors: [indigo, violet, pink, peach], startPoint: .top, endPoint: .bottom)

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12

    static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var hairline: Color {
        Color.primary.opacity(0.08)
    }

    static var subtleFill: Color {
        Color.primary.opacity(0.045)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct BackdropGlow: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let strength = colorScheme == .dark ? 0.42 : 0.26
            ZStack(alignment: .top) {
                glow(Theme.indigo, strength, width: width * 0.9, height: 360)
                    .offset(x: -width * 0.28, y: -170)
                glow(Theme.pink, strength, width: width * 0.85, height: 340)
                    .offset(x: width * 0.3, y: -165)
                glow(Theme.violet, strength * 0.85, width: width * 0.7, height: 300)
                    .offset(y: -150)
            }
            .frame(width: width, alignment: .top)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    func glow(_ color: Color, _ opacity: Double, width: CGFloat, height: CGFloat) -> some View {
        EllipticalGradient(
            colors: [color.opacity(opacity), color.opacity(opacity * 0.5), color.opacity(opacity * 0.12), color.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .frame(width: width, height: height)
    }
}

enum Format {
    static func bytes(_ value: Int64?) -> String? {
        guard let value, value > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = value >= 1_000_000_000 ? [.useGB] : value >= 1_000_000 ? [.useMB] : [.useKB]
        return formatter.string(fromByteCount: value)
    }

    static func approximateBytes(_ value: Int64?) -> String? {
        bytes(value).map { "≈ \($0)" }
    }

    static func speed(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return (bytes(Int64(value)) ?? "") + "/s"
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func eta(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 60 {
            return "\(Int(seconds))s left"
        }
        return (duration(seconds) ?? "") + " left"
    }

    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }
}
