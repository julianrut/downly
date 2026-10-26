import AppKit
import DownlyCore
import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) var model

    var tools: [ToolID] {
        ToolID.allCases.filter { model.toolPhases[$0] != nil }
    }

    var overall: Double {
        let values = tools.map { tool -> Double in
            switch model.toolPhases[tool] {
            case .downloading(let fraction): return fraction * 0.9
            case .installing: return 0.95
            case .ready: return 1
            default: return 0
            }
        }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var failure: String? {
        if case .failed(let message) = model.setup { return message }
        return nil
    }

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 20)
            ZStack {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 150, height: 150)
                    .blur(radius: 50)
                    .opacity(0.45)
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
            }
            VStack(spacing: 8) {
                Text(failure == nil ? "Getting Downly ready" : "Setup needs another try")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(failure == nil
                     ? "Downloading the engine that powers every download.\nThis happens once and takes about a minute."
                     : "Something interrupted the download. Check your connection and try again.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                    ToolRow(tool: tool, phase: model.toolPhases[tool] ?? .waiting)
                    if index < tools.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .card(padding: 8)
            .frame(maxWidth: 440)

            if let failure {
                VStack(spacing: 12) {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: 440)
                    Button("Try Again") {
                        model.retrySetup()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                VStack(spacing: 8) {
                    DownloadProgressBar(fraction: overall, height: 6)
                        .frame(width: 280)
                    Text("\(Int(overall * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToolRow: View {
    let tool: ToolID
    let phase: ToolInstallPhase

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.brand)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            trailing
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    var symbol: String {
        switch tool {
        case .ytdlp: return "arrow.down.circle"
        case .ffmpeg: return "film.stack"
        case .ffprobe: return "waveform.path.ecg"
        case .deno: return "bolt"
        }
    }

    var detail: String {
        switch phase {
        case .waiting: return tool.purpose
        case .downloading: return "Downloading…"
        case .installing: return "Installing…"
        case .ready(let version): return "Ready · \(version)"
        case .failed(let message): return message
        }
    }

    @ViewBuilder
    var trailing: some View {
        switch phase {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
        case .downloading(let fraction):
            DownloadProgressBar(fraction: fraction, height: 4)
                .frame(width: 64)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
