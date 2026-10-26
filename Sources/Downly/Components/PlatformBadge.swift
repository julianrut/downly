import DownlyCore
import SwiftUI

struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 20

    var body: some View {
        Group {
            switch platform {
            case .youtube: youtube
            case .spotify: spotify
            case .instagram: instagram
            case .tiktok: tiktok
            case .web: web
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(platform.displayName)
    }

    private var youtube: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: 0xFF0033))
            .frame(width: size, height: size * 0.74)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.36, weight: .black))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.02)
            }
    }

    private var spotify: some View {
        ZStack {
            Circle().fill(Color(hex: 0x1ED760))
            SpotifyWaves()
                .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .padding(size * 0.2)
        }
    }

    private var instagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF), Color(hex: 0x4F5BD5)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ))
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .strokeBorder(.white, lineWidth: size * 0.075)
                .padding(size * 0.2)
            Circle()
                .strokeBorder(.white, lineWidth: size * 0.075)
                .frame(width: size * 0.32, height: size * 0.32)
            Circle()
                .fill(.white)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.17, y: -size * 0.17)
        }
    }

    private var tiktok: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(hex: 0x111111))
            note.foregroundStyle(Color(hex: 0x25F4EE)).offset(x: -size * 0.035, y: -size * 0.03)
            note.foregroundStyle(Color(hex: 0xFE2C55)).offset(x: size * 0.035, y: size * 0.03)
            note.foregroundStyle(.white)
        }
    }

    private var note: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.52, weight: .heavy))
    }

    private var web: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.25))
            Image(systemName: "globe")
                .font(.system(size: size * 0.6, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpotifyWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let rows: [(y: CGFloat, inset: CGFloat, bend: CGFloat)] = [(0.22, 0.02, 0.12), (0.5, 0.1, 0.1), (0.76, 0.18, 0.08)]
        for row in rows {
            let start = CGPoint(x: rect.minX + w * row.inset, y: rect.minY + h * row.y)
            let end = CGPoint(x: rect.maxX - w * (row.inset + 0.02), y: rect.minY + h * (row.y + 0.06))
            let control = CGPoint(x: rect.midX, y: rect.minY + h * (row.y - row.bend))
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
        return path
    }
}

struct PlatformStrip: View {
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 14) {
            ForEach([Platform.youtube, .spotify, .instagram, .tiktok], id: \.self) { platform in
                HStack(spacing: 6) {
                    PlatformBadge(platform: platform, size: size)
                    Text(platform.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
