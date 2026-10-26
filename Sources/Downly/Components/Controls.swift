import DownlyCore
import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(height: compact ? 30 : 40)
            .background {
                Capsule(style: .continuous)
                    .fill(Theme.brandHorizontal)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                    }
            }
            .shadow(color: Theme.violet.opacity(isEnabled ? 0.38 : 0), radius: 12, y: 5)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SoftButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 26 : 32)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07)))
            .contentShape(Capsule())
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(label: configuration.label, isPressed: configuration.isPressed, size: size)
    }
}

struct IconButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let size: CGFloat
    @State var hovering = false

    var body: some View {
        label
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(isPressed ? 0.14 : (hovering ? 0.08 : 0))))
            .contentShape(Circle())
            .onHover { hovering = $0 }
    }
}

struct GradientCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.brand))
            .shadow(color: Theme.violet.opacity(0.35), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ModePicker: View {
    @Binding var selection: DownloadMode
    @Namespace var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DownloadMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = mode
                    }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background {
                            if selection == mode {
                                Capsule(style: .continuous)
                                    .fill(Theme.cardBackground)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "mode", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct OptionChip: View {
    let title: String
    let caption: String
    var footnote: String?
    var badge: String?
    let selected: Bool
    let action: () -> Void

    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let footnote {
                    Text(footnote)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.10) : Color.primary.opacity(hovering ? 0.07 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.06)), lineWidth: selected ? 1.6 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct DownloadProgressBar: View {
    let fraction: Double?
    var height: CGFloat = 5
    @State var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let fraction {
                    Capsule()
                        .fill(Theme.brandHorizontal)
                        .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else {
                    Capsule()
                        .fill(Theme.brandHorizontal)
                        .frame(width: proxy.size.width * 0.28)
                        .offset(x: sweep ? proxy.size.width * 0.72 : 0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                sweep = true
                            }
                        }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct SelectionMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.black.opacity(0.25)))
            Circle()
                .strokeBorder(.white.opacity(selected ? 0 : 0.9), lineWidth: 1.5)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

struct CheckRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.6)))
                content()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
