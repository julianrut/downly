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
            let strength = colorScheme == .dark ? 0.34 : 0.2
            ZStack {
                glow(Theme.indigo, strength, center: UnitPoint(x: 0.18, y: 0), radius: width * 0.55)
                glow(Theme.pink, strength, center: UnitPoint(x: 0.85, y: 0), radius: width * 0.5)
                glow(Theme.violet, strength * 0.9, center: UnitPoint(x: 0.5, y: 0), radius: width * 0.42)
            }
            .frame(width: width, height: 340)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    func glow(_ color: Color, _ opacity: Double, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(opacity * 0.45), color.opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        .scaleEffect(x: 1, y: 0.62, anchor: .top)
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
