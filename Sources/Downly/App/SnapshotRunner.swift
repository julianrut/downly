import AppKit
import DownlyCore
import SwiftUI

@MainActor
enum SnapshotRunner {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func run(into directory: URL, delegate: AppDelegate) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var window: NSWindow?
        for _ in 0..<50 {
            window = NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
            if window != nil, delegate.model != nil { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let window, let model = delegate.model else {
            print("snapshot: no window")
            exit(2)
        }
        window.setContentSize(NSSize(width: 800, height: 780))
        window.center()
        NSApp.activate(ignoringOtherApps: true)

        model.setup = .installing
        model.toolPhases = [.ytdlp: .downloading(0.64), .ffmpeg: .ready("8.1.2"), .ffprobe: .installing, .deno: .downloading(0.28)]
        await capture(window, "01-setup", in: directory)

        model.setup = .ready
        model.analysis = .idle
        model.downloads.items = []
        await capture(window, "02-home", in: directory)

        let youtube = ParsedLink(url: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, platform: .youtube, kind: .youtubeVideo(id: "aqz-KE-bpKQ"))
        model.input = youtube.url.absoluteString
        model.analysisID = UUID()
        model.analysis = .loaded(youtube, .video(DemoData.video))
        await capture(window, "03-video", in: directory)

        model.analysisID = UUID()
        model.analysis = .loading(youtube, DemoData.video.summary)
        await capture(window, "04-loading", in: directory)

        model.input = ""
        model.analysis = .idle
        model.downloads.items = DemoData.downloads()
        model.clipboardSuggestion = ParsedLink(url: URL(string: "https://www.tiktok.com/@scout2015/video/6718335390845095173")!, platform: .tiktok, kind: .tiktokVideo(id: "6718335390845095173"))
        await capture(window, "05-downloads", in: directory)
        model.clipboardSuggestion = nil

        NSApp.appearance = NSAppearance(named: .darkAqua)
        let spotify = ParsedLink(url: URL(string: "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4")!, platform: .spotify, kind: .spotifyAlbum(id: "6N9PS4QXF1D0OWPk0Sxtb4"), isMusic: true)
        model.input = spotify.url.absoluteString
        model.analysisID = UUID()
        model.analysis = .loaded(spotify, .music(DemoData.album))
        await capture(window, "06-spotify-dark", in: directory)

        let instagram = ParsedLink(url: URL(string: "https://www.instagram.com/p/BQ0eAlwhDrw/")!, platform: .instagram, kind: .instagramPost(shortcode: "BQ0eAlwhDrw"))
        model.input = instagram.url.absoluteString
        model.analysisID = UUID()
        model.analysis = .loaded(instagram, .gallery(DemoData.gallery))
        await capture(window, "07-instagram-dark", in: directory)

        model.analysisID = UUID()
        model.analysis = .loaded(youtube, .video(DemoData.video))
        await capture(window, "08-video-dark", in: directory)

        NSApp.appearance = NSAppearance(named: .aqua)
        model.analysisID = UUID()
        model.analysis = .failed(youtube, "YouTube asked to confirm you’re not a bot.", DownlyError.botCheck.recoverySuggestion, true)
        await capture(window, "09-error", in: directory)

        model.analysis = .idle
        model.input = ""
        model.downloads.items = []
        for (tab, name) in [(SettingsTab.formats, "10-settings-formats"), (SettingsTab.accounts, "11-settings-accounts")] {
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = "Settings"
            settings.contentView = NSHostingView(rootView: SettingsView(tab: tab).environment(model).tint(Theme.accent))
            settings.center()
            settings.makeKeyAndOrderFront(nil)
            await capture(settings, name, in: directory)
            settings.orderOut(nil)
        }
        print("snapshot: done")
        exit(0)
    }

    static func capture(_ window: NSWindow, _ name: String, in directory: URL) async {
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent("\(name).png"))
            print("snapshot: wrote \(name)")
        }
    }
}

@MainActor
enum DemoData {
    static let video: VideoAnalysis = {
        let summary = MediaSummary(
            title: "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film",
            author: "Blender",
            thumbnail: URL(string: "https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.jpg"),
            duration: 635,
            platform: .youtube,
            webpageURL: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
        )
        let formats = [
            MediaFormat(id: "571", ext: "mp4", vcodec: "av01.0.16M.08", acodec: "none", width: 7680, height: 4320, fps: 60, tbr: 36000, note: "4320p60"),
            MediaFormat(id: "315", ext: "webm", vcodec: "vp9", acodec: "none", width: 3840, height: 2160, fps: 60, tbr: 24000, note: "2160p60"),
            MediaFormat(id: "308", ext: "webm", vcodec: "vp9", acodec: "none", width: 2560, height: 1440, fps: 60, tbr: 11000, note: "1440p60"),
            MediaFormat(id: "299", ext: "mp4", vcodec: "avc1.64002a", acodec: "none", width: 1920, height: 1080, fps: 60, tbr: 6000, note: "1080p60"),
            MediaFormat(id: "298", ext: "mp4", vcodec: "avc1.4d4020", acodec: "none", width: 1280, height: 720, fps: 60, tbr: 3400, note: "720p60"),
            MediaFormat(id: "135", ext: "mp4", vcodec: "avc1.4d401f", acodec: "none", width: 854, height: 480, fps: 30, tbr: 1200, note: "480p"),
            MediaFormat(id: "134", ext: "mp4", vcodec: "avc1.4d401e", acodec: "none", width: 640, height: 360, fps: 30, tbr: 650, note: "360p"),
            MediaFormat(id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", tbr: 129, abr: 129),
            MediaFormat(id: "251", ext: "webm", vcodec: "none", acodec: "opus", tbr: 140, abr: 140),
        ]
        return VideoAnalysis(summary: summary, id: "aqz-KE-bpKQ", sourceURL: summary.webpageURL.absoluteString, formats: formats, playlistURL: nil)
    }()

    static let album: MusicCollection = {
        let cover = URL(string: "https://image-cdn-ak.spotifycdn.com/image/ab67616d0000b273baf89eb11ec7c657805d2da0")
        let titles: [(String, Int)] = [
            ("Never Gonna Give You Up", 213), ("Whenever You Need Somebody", 234), ("Together Forever", 205),
            ("It Would Take a Strong Strong Man", 222), ("The Love Has Gone", 260), ("Don’t Say Goodbye", 251),
            ("Slipping Away", 233), ("No More Looking for Love", 196), ("You Move Me", 223), ("When I Fall in Love", 183),
        ]
        let tracks = titles.enumerated().map { index, item in
            SpotifyTrack(id: "t\(index)", title: item.0, artists: ["Rick Astley"], album: "Whenever You Need Somebody", durationMs: item.1 * 1000, cover: cover, releaseDate: "1987-11-12", trackNumber: index + 1)
        }
        let summary = MediaSummary(title: "Whenever You Need Somebody", author: "Rick Astley · 1987", thumbnail: cover, duration: nil, platform: .spotify, webpageURL: URL(string: "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4")!)
        return MusicCollection(summary: summary, kind: .album, tracks: tracks, totalTracks: tracks.count)
    }()

    static let gallery: Gallery = {
        let images = [
            "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600",
            "https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=600",
            "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=600",
            "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=600",
        ]
        let items = images.enumerated().map { index, string in
            GalleryItem(id: "i\(index)", kind: index == 2 ? .video : .photo, url: URL(string: string)!, thumbnail: URL(string: string), width: 1080, height: 1350, suggestedName: "post \(index + 1)")
        }
        let summary = MediaSummary(title: "Golden hour somewhere quiet ✨", author: "@instagram", thumbnail: items.first?.thumbnail, platform: .instagram, webpageURL: URL(string: "https://www.instagram.com/p/BQ0eAlwhDrw/")!)
        return Gallery(summary: summary, sections: [GallerySection(id: "post", title: "4 items", items: items)], folderName: "instagram post")
    }()

    static func downloads() -> [DownloadItem] {
        func job(_ title: String, _ subtitle: String, _ detail: String, _ thumb: String?, _ platform: Platform, audio: Bool = false) -> DownloadJob {
            let kind: JobKind = audio
                ? .audio(url: "https://example.com", format: .mp3, squareCover: true)
                : .video(url: "https://example.com", selector: "b", sort: nil, container: .mp4, appleCompatible: true, expectedSizes: [:])
            return DownloadJob(title: title, subtitle: subtitle, detail: detail, thumbnail: thumb.flatMap(URL.init(string:)), platform: platform, kind: kind)
        }
        let running = DownloadItem(job: job("Big Buck Bunny 60fps 4K", "Blender", "4K · MP4", "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg", .youtube))
        running.state = .running
        running.phase = .downloading
        running.fraction = 0.46
        running.downloaded = 512_000_000
        running.total = 1_110_000_000
        running.speed = 18_400_000
        running.eta = 33

        let merging = DownloadItem(job: job("Never Gonna Give You Up", "Rick Astley", "MP3 · 320 kbps", "https://image-cdn-ak.spotifycdn.com/image/ab67616d0000b273baf89eb11ec7c657805d2da0", .spotify, audio: true))
        merging.state = .running
        merging.phase = .processing("Adding cover art & tags")

        let finding = DownloadItem(job: job("Together Forever", "Rick Astley", "MP3 · 320 kbps", "https://image-cdn-ak.spotifycdn.com/image/ab67616d0000b273baf89eb11ec7c657805d2da0", .spotify, audio: true))
        finding.state = .running
        finding.phase = .preparing("Finding on YouTube Music")

        let queued = DownloadItem(job: job("Scramble up ur name & I’ll try to guess it", "@scout2015", "720p · MP4", "https://images.unsplash.com/photo-1543852786-1cf6624b9987?w=400", .tiktok))

        let done = DownloadItem(job: job("Golden hour somewhere quiet ✨", "@instagram", "3 photos · 1 video", "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=400", .instagram))
        done.state = .finished
        done.fraction = 1

        let failed = DownloadItem(job: job("Members-only livestream", "Some Channel", "1080p · MP4", "https://i.ytimg.com/vi/aqz-KE-bpKQ/mqdefault.jpg", .youtube))
        failed.state = .failed("This video is for channel members only.")

        return [running, merging, finding, queued, done, failed]
    }
}
