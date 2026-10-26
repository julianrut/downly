import AppKit
import DownlyCore
import SwiftUI

struct DownloadsSection: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let manager = model.downloads
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Downloads")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if manager.activeCount > 0 {
                    Text("\(manager.activeCount) in progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                if manager.hasFinished {
                    Button("Clear") {
                        manager.clearFinished()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("Remove finished downloads from the list (files stay on disk)")
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                    DownloadRow(item: item)
                    if index < manager.items.count - 1 {
                        Divider()
                            .padding(.leading, 86)
                            .opacity(0.6)
                    }
                }
            }
            .card(padding: 6)
        }
    }
}

struct DownloadRow: View {
    @Environment(AppModel.self) var model
    let item: DownloadItem
    @State var hovering = false

    var manager: DownloadManager {
        model.downloads
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(item.job.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                status
                if item.isActive {
                    DownloadProgressBar(fraction: item.state == .queued ? 0 : item.fraction)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.045 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if item.isFinished {
                manager.open(item)
            }
        }
        .contextMenu { menu }
        .onDrag {
            if item.isFinished, let file = item.files.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return NSItemProvider(contentsOf: item.files.count > 1 ? (item.revealTarget ?? file) : file) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
    }

    var isSquare: Bool {
        item.job.isAudio || item.job.platform == .spotify
    }

    var thumbnail: some View {
        RemoteImage(url: item.job.thumbnail)
            .frame(width: isSquare ? 46 : 64, height: isSquare ? 46 : 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                PlatformBadge(platform: item.job.platform, size: 15)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: 5, y: 5)
            }
            .frame(width: 64, height: 46)
    }

    @ViewBuilder
    var status: some View {
        switch item.state {
        case .queued:
            statusText("Waiting to start…", symbol: "clock")
        case .running:
            statusText(runningText, symbol: nil)
        case .finished:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(finishedText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        case .failed(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .font(.caption)
            .help(item.failureHint ?? message)
        case .cancelled:
            statusText("Cancelled", symbol: "xmark.circle")
        }
    }

    func statusText(_ text: String, symbol: String?) -> some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .lineLimit(1)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    var runningText: String {
        switch item.phase {
        case .preparing(let message):
            if let note = item.note, message.contains("Downloading") {
                return note
            }
            return message + "…"
        case .processing(let message):
            if let fraction = item.fraction, fraction > 0 {
                return "\(message)… \(Int(fraction * 100))%"
            }
            return message + "…"
        case .downloading, .none:
            var parts: [String] = []
            if let downloaded = Format.bytes(item.downloaded), let total = Format.bytes(item.total) {
                parts.append("\(downloaded) of \(total)")
            } else if let fraction = item.fraction {
                parts.append("\(Int(fraction * 100))%")
            } else {
                parts.append("Downloading")
            }
            if let speed = Format.speed(item.speed) {
                parts.append(speed)
            }
            if let eta = Format.eta(item.eta) {
                parts.append(eta)
            }
            return parts.joined(separator: " · ")
        }
    }

    var finishedText: String {
        var parts = [item.job.detail]
        if let size = Format.bytes(item.fileSize) {
            parts.append(size)
        }
        if !item.filesExist {
            parts.append("moved or deleted")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    var actions: some View {
        HStack(spacing: 2) {
            switch item.state {
            case .queued, .running:
                Button {
                    manager.cancel(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Cancel")
            case .finished:
                Button {
                    manager.open(item)
                } label: {
                    Image(systemName: item.files.count > 1 ? "folder" : "play.fill")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help(item.files.count > 1 ? "Open folder" : "Open")
                .disabled(!item.filesExist)
                Button {
                    manager.reveal(item)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Show in Finder")
                .disabled(!item.filesExist)
            case .failed, .cancelled:
                Button {
                    manager.retry(item)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Try again")
                Button {
                    manager.remove(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Remove")
            }
        }
    }

    @ViewBuilder
    var menu: some View {
        if item.isFinished {
            Button("Open") { manager.open(item) }
            Button("Show in Finder") { manager.reveal(item) }
            Divider()
        }
        if let source = item.job.sourceURL {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
            }
            Button("Open Original Page") {
                if let url = URL(string: source) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        Divider()
        if item.isActive {
            Button("Cancel") { manager.cancel(item) }
        } else {
            Button(item.isFinished ? "Download Again" : "Try Again") { manager.retry(item) }
            Button("Remove from List") { manager.remove(item) }
        }
    }
}

extension DownloadJob {
    var sourceURL: String? {
        switch kind {
        case .video(let url, _, _, _, _, _): return url
        case .audio(let url, _, _): return url
        case .spotify(let track, _, _): return "https://open.spotify.com/track/\(track.id)"
        case .gallery(let items, _): return items.first?.ytdlpURL
        }
    }
}
