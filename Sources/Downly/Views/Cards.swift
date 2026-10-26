import AppKit
import DownlyCore
import SwiftUI

enum ThumbnailShape {
    case wide
    case square
    case portrait
    case circle
}

struct MediaHeader: View {
    @Environment(AppModel.self) var model
    let summary: MediaSummary
    var badge: String?
    var shape: ThumbnailShape = .wide
    var closable = true

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnail
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    PlatformBadge(platform: summary.platform, size: 15)
                    Text(summary.platform.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let badge {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(badge)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(summary.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let author = summary.author, !author.isEmpty {
                    Text(author)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            if closable {
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Close")
            }
        }
    }

    @ViewBuilder
    var thumbnail: some View {
        switch shape {
        case .wide:
            RemoteImage(url: summary.thumbnail)
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) { durationBadge }
        case .portrait:
            RemoteImage(url: summary.thumbnail)
                .frame(width: 74, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) { durationBadge }
        case .square:
            RemoteImage(url: summary.thumbnail)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .circle:
            RemoteImage(url: summary.thumbnail)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .padding(4)
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF)], startPoint: .bottomLeading, endPoint: .topTrailing),
                        lineWidth: 3
                    )
                }
        }
    }

    @ViewBuilder
    var durationBadge: some View {
        if let duration = Format.duration(summary.duration) {
            Text(duration)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.65)))
                .padding(6)
        }
    }
}

struct LoadingCard: View {
    let link: ParsedLink
    let summary: MediaSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summary {
                MediaHeader(summary: summary, shape: link.platform == .spotify ? .square : .wide)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: link.platform == .spotify ? 104 : 176, height: link.platform == .spotify ? 104 : 99)
                        .shimmering()
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(width: 90, height: 10)
                        SkeletonBlock(width: 280, height: 16)
                        SkeletonBlock(width: 150, height: 12)
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 60)
                        .shimmering()
                }
            }
        }
        .card(padding: 20)
    }

    var loadingText: String {
        switch link.platform {
        case .youtube: return "Finding every quality…"
        case .spotify: return "Reading from Spotify…"
        case .instagram: return "Opening Instagram…"
        case .tiktok: return "Opening TikTok…"
        case .web: return "Looking for media…"
        }
    }
}

struct ErrorCard: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink?
    let message: String
    let suggestion: String?
    let needsAccount: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: needsAccount ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let suggestion {
                    Text(suggestion)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if link != nil {
                        Button("Try Again") {
                            model.retryAnalysis()
                        }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                    }
                    if needsAccount {
                        SettingsLink {
                            Text("Open Settings")
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    Button("Dismiss") {
                        model.clear()
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 20)
    }
}

struct CardFooter<Leading: View>: View {
    let title: String
    let detail: String?
    let enabled: Bool
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            Spacer(minLength: 8)
            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                    Text(title)
                    if let detail {
                        Text(detail)
                            .opacity(0.75)
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!enabled)
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct FootnoteLabel: View {
    let symbol: String
    let text: String
    var highlight = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(highlight ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary))
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.caption)
    }
}

struct AudioFormatGrid: View {
    @Binding var selection: AudioFormat
    let duration: Double?
    let source: MediaFormat?
    var formats: [AudioFormat] = AudioFormat.allCases

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 200), spacing: 10)], spacing: 10) {
            ForEach(formats, id: \.self) { format in
                OptionChip(
                    title: format.title,
                    caption: format.shortDetail,
                    footnote: Format.approximateBytes(format.estimatedBytes(duration: duration, source: source)),
                    selected: selection == format
                ) {
                    selection = format
                }
            }
        }
    }
}

struct VideoCard: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink
    let video: VideoAnalysis

    @State var mode: DownloadMode = Preferences.defaultMode
    @State var tier: Int?
    @State var audioFormat: AudioFormat = Preferences.audioFormat
    @State var container: VideoContainer = Preferences.videoContainer
    @AppStorage(PrefKey.appleCompatible) var appleCompatible = true
    @AppStorage(PrefKey.preferHDR) var preferHDR = false

    var effectiveMode: DownloadMode {
        video.hasVideo ? mode : .audio
    }

    var preferences: VideoPreferences {
        VideoPreferences(container: container, appleCompatible: appleCompatible && container == .mp4, preferHDR: preferHDR)
    }

    var choices: [VideoChoice] {
        FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: preferences, preferMuxed: link.platform != .youtube)
    }

    var selectedChoice: VideoChoice? {
        let all = choices
        return all.first { $0.tier == tier } ?? all.first
    }

    var sourceAudio: MediaFormat? {
        FormatPlanner.bestAudio(video.formats, preferAAC: audioFormat != .opus)
    }

    var isVertical: Bool {
        guard let best = choices.first?.video else { return false }
        return (best.height ?? 0) > (best.width ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MediaHeader(summary: video.summary, badge: video.isLive ? "Live" : nil, shape: isVertical ? .portrait : .wide)

            if let playlistURL = video.playlistURL {
                Button {
                    model.analyzePlaylist(url: playlistURL, platform: link.platform)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("This video is part of a playlist")
                        Text("Show all")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.brand)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }

            HStack {
                if video.hasVideo {
                    ModePicker(selection: $mode)
                }
                Spacer()
                if effectiveMode == .video {
                    Picker("Format", selection: $container) {
                        ForEach(VideoContainer.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Container format")
                }
            }

            if effectiveMode == .video {
                if choices.isEmpty {
                    FootnoteLabel(symbol: "exclamationmark.circle", text: "No downloadable video streams were found. Try Audio instead.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 200), spacing: 10)], spacing: 10) {
                        ForEach(choices) { choice in
                            OptionChip(
                                title: choice.label,
                                caption: caption(for: choice),
                                footnote: Format.approximateBytes(choice.estimatedBytes),
                                badge: choice.isHDR ? "HDR" : nil,
                                selected: choice.tier == selectedChoice?.tier
                            ) {
                                tier = choice.tier
                            }
                        }
                    }
                }
            } else {
                AudioFormatGrid(selection: $audioFormat, duration: video.summary.duration, source: sourceAudio)
            }

            CardFooter(title: "Download", detail: footerSize, enabled: effectiveMode == .audio || selectedChoice != nil, action: download) {
                footnote
            }
        }
        .card(padding: 20)
        .onAppear {
            if tier == nil {
                tier = defaultTier
            }
        }
    }

    var defaultTier: Int? {
        let preferred = Preferences.defaultQuality
        let all = choices
        guard preferred > 0 else { return all.first?.tier }
        return all.first { $0.tier <= preferred }?.tier ?? all.last?.tier
    }

    var footerSize: String? {
        if effectiveMode == .video {
            return Format.bytes(selectedChoice?.estimatedBytes)
        }
        return Format.bytes(audioFormat.estimatedBytes(duration: video.summary.duration, source: sourceAudio))
    }

    @ViewBuilder
    var footnote: some View {
        if effectiveMode == .video, let choice = selectedChoice {
            if choice.needsTranscode {
                FootnoteLabel(symbol: "wand.and.stars", text: "\(choice.video.codecFamily.displayName) stream is converted to HEVC so it plays in QuickTime & Photos", highlight: true)
            } else {
                let audioText = choice.audio == nil ? "with sound" : "+ \(audioName(choice.audio)) audio"
                FootnoteLabel(symbol: "checkmark.seal", text: "\(container.title) · \(choice.video.codecFamily.displayName) \(audioText)")
            }
        } else {
            FootnoteLabel(symbol: "music.note", text: "\(audioFormat.title) · \(audioFormat.detail)\(audioFormat.supportsCoverArt ? " · with cover art" : "")")
        }
    }

    func audioName(_ format: MediaFormat?) -> String {
        switch format?.audioCodecFamily {
        case .aac: return "AAC"
        case .opus: return "Opus"
        case .mp3: return "MP3"
        default: return "best"
        }
    }

    func caption(for choice: VideoChoice) -> String {
        var parts = [choice.caption]
        if let fps = choice.fps, fps > 30 {
            parts.append("\(fps) fps")
        }
        return parts.joined(separator: " · ")
    }

    func download() {
        let summary = video.summary
        let subtitle = summary.author ?? link.platform.displayName
        if effectiveMode == .video, let choice = selectedChoice {
            var expected: [String: Int64] = [:]
            if let size = choice.video.estimatedBytes(duration: summary.duration) {
                expected[choice.video.id] = size
            }
            if let audio = choice.audio, let size = audio.estimatedBytes(duration: summary.duration) {
                expected[audio.id] = size
            }
            let detail = [choice.label, container.title].joined(separator: " · ")
            let job = DownloadJob(
                title: summary.title,
                subtitle: subtitle,
                detail: detail,
                thumbnail: summary.thumbnail,
                platform: link.platform,
                kind: .video(url: video.sourceURL, selector: choice.selector, sort: nil, container: container, appleCompatible: preferences.appleCompatible, expectedSizes: expected)
            )
            model.enqueue([job])
        } else {
            let job = DownloadJob(
                title: summary.title,
                subtitle: subtitle,
                detail: "\(audioFormat.title) · \(audioFormat.shortDetail)",
                thumbnail: summary.thumbnail,
                platform: link.platform,
                kind: .audio(url: video.sourceURL, format: audioFormat, squareCover: video.isMusicSource)
            )
            model.enqueue([job])
        }
    }
}

struct PlaylistCard: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink
    let playlist: PlaylistAnalysis

    @State var mode: DownloadMode = Preferences.defaultMode
    @State var quality: Int = Preferences.defaultQuality
    @State var audioFormat: AudioFormat = Preferences.audioFormat
    @State var selected: Set<String> = []
    @State var prepared = false

    static let qualityOptions = [2160, 1440, 1080, 720, 480, 360]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaHeader(summary: playlist.summary, badge: Format.count(playlist.entries.count, "video"))

            HStack {
                ModePicker(selection: $mode)
                Spacer()
                if mode == .video {
                    Picker("Quality", selection: $quality) {
                        Text("Best available").tag(0)
                        ForEach(Self.qualityOptions, id: \.self) { value in
                            Text("Up to \(FormatPlanner.label(for: value))").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if mode == .audio {
                AudioFormatGrid(selection: $audioFormat, duration: nil, source: nil)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(selected.count == playlist.entries.count ? "All \(playlist.entries.count) selected" : "\(selected.count) of \(playlist.entries.count) selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(selected.count == playlist.entries.count ? "Select None" : "Select All") {
                        if selected.count == playlist.entries.count {
                            selected.removeAll()
                        } else {
                            selected = Set(playlist.entries.map(\.id))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                            CheckRow(selected: selected.contains(entry.id), action: { toggle(entry.id) }) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24, alignment: .trailing)
                                RemoteImage(url: entry.thumbnail)
                                    .frame(width: 64, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title)
                                        .font(.callout)
                                        .lineLimit(1)
                                    if let author = entry.author {
                                        Text(author)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let duration = Format.duration(entry.duration) {
                                    Text(duration)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))

            CardFooter(title: selected.count == 1 ? "Download 1 video" : "Download \(selected.count) videos", detail: nil, enabled: !selected.isEmpty, action: download) {
                FootnoteLabel(symbol: mode == .video ? "film.stack" : "music.note.list", text: mode == .video ? "Each video is saved with sound in the best quality up to your choice" : "\(audioFormat.title) · \(audioFormat.detail)")
            }
        }
        .card(padding: 20)
        .onAppear {
            if !prepared {
                selected = Set(playlist.entries.map(\.id))
                prepared = true
            }
        }
    }

    func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func download() {
        let preferences = Preferences.videoPreferences
        let plan = FormatPlanner.playlistSelector(tier: quality == 0 ? nil : quality, preferences: preferences)
        let qualityLabel = quality == 0 ? "Best" : FormatPlanner.label(for: quality)
        let jobs: [DownloadJob] = playlist.entries.filter { selected.contains($0.id) }.map { entry in
            var url = entry.url
            if !url.hasPrefix("http") {
                url = link.platform == .youtube ? "https://www.youtube.com/watch?v=\(entry.id)" : url
            }
            let subtitle = entry.author ?? playlist.summary.title
            if mode == .video {
                return DownloadJob(
                    title: entry.title,
                    subtitle: subtitle,
                    detail: "\(qualityLabel) · \(preferences.container.title)",
                    thumbnail: entry.thumbnail,
                    platform: link.platform,
                    kind: .video(url: url, selector: plan.selector, sort: plan.sort, container: preferences.container, appleCompatible: preferences.appleCompatible, expectedSizes: [:])
                )
            }
            return DownloadJob(
                title: entry.title,
                subtitle: subtitle,
                detail: "\(audioFormat.title) · \(audioFormat.shortDetail)",
                thumbnail: entry.thumbnail,
                platform: link.platform,
                kind: .audio(url: url, format: audioFormat, squareCover: link.isMusic)
            )
        }
        model.enqueue(jobs)
    }
}

struct MusicCard: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink
    let collection: MusicCollection

    @State var format: AudioFormat = Preferences.musicFormat
    @State var selected: Set<String> = []
    @State var prepared = false

    var isSingle: Bool {
        collection.kind == .track
    }

    var badge: String {
        switch collection.kind {
        case .track: return "Song"
        case .album: return "Album · " + Format.count(collection.tracks.count, "song")
        case .playlist: return "Playlist · " + Format.count(collection.tracks.count, "song")
        case .artist: return "Top songs · \(collection.tracks.count)"
        }
    }

    var selectedTracks: [SpotifyTrack] {
        isSingle ? collection.tracks : collection.tracks.filter { selected.contains($0.id) }
    }

    var selectedDuration: Double {
        selectedTracks.compactMap(\.duration).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaHeader(summary: collection.summary, badge: badge, shape: .square)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.brand)
                Text("Downly finds each song on YouTube Music, then adds Spotify’s cover art and tags.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.07)))

            AudioFormatGrid(selection: $format, duration: selectedDuration > 0 ? selectedDuration : nil, source: nil, formats: [.mp3, .m4a, .flac, .opus, .wav])

            if !isSingle {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(selected.count) of \(collection.tracks.count) selected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(selected.count == collection.tracks.count ? "Select None" : "Select All") {
                            if selected.count == collection.tracks.count {
                                selected.removeAll()
                            } else {
                                selected = Set(collection.tracks.map(\.id))
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(collection.tracks.enumerated()), id: \.element.id) { index, track in
                                CheckRow(selected: selected.contains(track.id), action: { toggle(track.id) }) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 5) {
                                            Text(track.title)
                                                .font(.callout)
                                                .lineLimit(1)
                                            if track.explicit {
                                                Text("E")
                                                    .font(.system(size: 9, weight: .heavy))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 13, height: 13)
                                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)))
                                            }
                                        }
                                        Text(track.artistLine)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if let duration = Format.duration(track.duration) {
                                        Text(duration)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
            }

            CardFooter(
                title: isSingle ? "Download song" : (selectedTracks.count == 1 ? "Download 1 song" : "Download \(selectedTracks.count) songs"),
                detail: nil,
                enabled: !selectedTracks.isEmpty,
                action: download
            ) {
                FootnoteLabel(symbol: "music.note", text: "\(format.title) · \(format.detail)")
            }
        }
        .card(padding: 20)
        .onAppear {
            if !prepared {
                selected = Set(collection.tracks.map(\.id))
                prepared = true
            }
        }
    }

    func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func download() {
        let folder = isSingle ? nil : collection.summary.title
        let jobs = selectedTracks.map { track in
            DownloadJob(
                title: track.title,
                subtitle: track.artistLine,
                detail: "\(format.title) · \(format.shortDetail)",
                thumbnail: track.cover ?? collection.summary.thumbnail,
                platform: .spotify,
                kind: .spotify(track: track, format: format, folder: folder)
            )
        }
        model.enqueue(jobs)
    }
}

struct GalleryCard: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink
    let gallery: Gallery

    @State var selected: Set<String> = []
    @State var prepared = false

    var chosen: [GalleryItem] {
        gallery.allItems.filter { selected.contains($0.id) }
    }

    var badge: String? {
        let items = gallery.allItems
        if gallery.isProfile { return "Profile" }
        return describe(items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaHeader(summary: gallery.summary, badge: badge, shape: gallery.isProfile ? .circle : .wide)

            ForEach(gallery.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if section.items.count > 1 {
                            let all = section.items.allSatisfy { selected.contains($0.id) }
                            Button(all ? "Select None" : "Select All") {
                                for item in section.items {
                                    if all { selected.remove(item.id) } else { selected.insert(item.id) }
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                        }
                    }
                    let minimum: CGFloat = gallery.allItems.count == 1 ? 200 : 104
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: gallery.allItems.count == 1 ? 260 : 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(section.items) { item in
                            GalleryTile(item: item, selected: selected.contains(item.id)) {
                                if selected.contains(item.id) {
                                    selected.remove(item.id)
                                } else {
                                    selected.insert(item.id)
                                }
                            }
                        }
                    }
                }
            }

            CardFooter(title: buttonTitle, detail: nil, enabled: !chosen.isEmpty, action: download) {
                FootnoteLabel(symbol: "sparkles", text: "Original resolution, straight from \(link.platform.displayName)")
            }
        }
        .card(padding: 20)
        .onAppear {
            if !prepared {
                selected = Set(gallery.allItems.map(\.id))
                prepared = true
            }
        }
    }

    var buttonTitle: String {
        let items = chosen
        if items.count == 1 {
            if gallery.isProfile, items[0].id.hasPrefix("pfp") { return "Download profile picture" }
            switch items[0].kind {
            case .photo: return "Download photo"
            case .video: return "Download video"
            case .audio: return "Download sound"
            }
        }
        return "Download \(items.count) items"
    }

    func describe(_ items: [GalleryItem]) -> String? {
        let photos = items.filter { $0.kind == .photo }.count
        let videos = items.filter { $0.kind == .video }.count
        let audio = items.filter { $0.kind == .audio }.count
        var parts: [String] = []
        if photos > 0 { parts.append(Format.count(photos, "photo")) }
        if videos > 0 { parts.append(Format.count(videos, "video")) }
        if audio > 0 { parts.append("sound") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func download() {
        let items = chosen
        guard !items.isEmpty else { return }
        let detail = describe(items) ?? "Media"
        let job = DownloadJob(
            title: gallery.summary.title,
            subtitle: gallery.summary.author ?? link.platform.displayName,
            detail: detail,
            thumbnail: items.first?.thumbnail ?? gallery.summary.thumbnail,
            platform: link.platform,
            kind: .gallery(items: items, folder: gallery.folderName)
        )
        model.enqueue([job])
    }
}

struct GalleryTile: View {
    let item: GalleryItem
    let selected: Bool
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if item.kind == .audio {
                        ZStack {
                            Theme.brand.opacity(0.85)
                            Image(systemName: "waveform")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    } else {
                        RemoteImage(url: item.thumbnail ?? (item.kind == .photo ? item.url : nil))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    SelectionMark(selected: selected)
                        .padding(7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: selected ? 2 : 1)
                }
                .scaleEffect(hovering ? 1.02 : 1)
                .opacity(selected ? 1 : 0.6)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
                .animation(.easeOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.resolutionLabel ?? "")
    }
}
