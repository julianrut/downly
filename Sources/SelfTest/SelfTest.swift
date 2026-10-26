import DownlyCore
import Foundation

@main
struct SelfTest {
    static var failures: [String] = []
    static var warnings: [String] = []

    static func main() async {
        let arguments = CommandLine.arguments
        let networkTests = !arguments.contains("--offline")
        let downloadTests = arguments.contains("--downloads")
        print("== Downly self-test ==")

        check("LinkParser recognises YouTube", LinkParser.parse("https://youtu.be/dQw4w9WgXcQ?t=3")?.kind == .youtubeVideo(id: "dQw4w9WgXcQ"))
        check("LinkParser recognises Shorts", LinkParser.parse("https://www.youtube.com/shorts/abc123XYZ00")?.kind == .youtubeVideo(id: "abc123XYZ00"))
        check("LinkParser recognises Spotify", LinkParser.parse("https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT?si=x")?.kind == .spotifyTrack(id: "4cOdK2wGLETKBW3PvgPWqT"))
        check("LinkParser recognises Instagram reel", LinkParser.parse("instagram.com/reel/C9xYz123abc/?igsh=1")?.kind == .instagramPost(shortcode: "C9xYz123abc"))
        check("LinkParser recognises Instagram profile", LinkParser.parse("https://www.instagram.com/natgeo/")?.kind == .instagramProfile(username: "natgeo"))
        check("LinkParser recognises TikTok photo", LinkParser.parse("https://www.tiktok.com/@user/photo/7300000000000000000")?.kind == .tiktokPhoto(id: "7300000000000000000"))
        check("Instagram shortcode decoding", InstagramClient.mediaID(fromShortcode: "B") == "1")

        guard networkTests else {
            finish()
            return
        }

        print("\n-- Installing components --")
        let started = Date()
        let toolchain = Toolchain.shared
        let tools: ToolPaths
        do {
            tools = try await toolchain.ensureInstalled { tool, phase in
                switch phase {
                case .ready(let version): print("  \(tool.displayName) ready: \(version)")
                case .failed(let error): print("  \(tool.displayName) FAILED: \(error)")
                default: break
                }
            }
        } catch {
            failures.append("Toolchain install: \(error.friendlyMessage)")
            finish()
            return
        }
        print(String(format: "  installed in %.1fs", Date().timeIntervalSince(started)))
        for (tool, version) in await toolchain.versions().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(tool.rawValue): \(version)")
        }
        let encoders = await EncoderCatalog.shared.encoders(ffmpeg: tools.ffmpeg)
        print("  encoders: hevc_videotoolbox=\(encoders.contains("hevc_videotoolbox")) h264_videotoolbox=\(encoders.contains("h264_videotoolbox")) libx264=\(encoders.contains("libx264")) libmp3lame=\(encoders.contains("libmp3lame")) libopus=\(encoders.contains("libopus")) aac=\(encoders.contains("aac"))")
        if let latest = await toolchain.latestYTDLPVersion() {
            print("  latest yt-dlp release: \(latest)")
        } else {
            warnings.append("Could not read latest yt-dlp version")
        }

        let analyzer = Analyzer(tools: tools, settings: EngineSettings())

        print("\n-- Spotify --")
        await soft("Spotify track") {
            let collection = try await SpotifyClient().fetch(type: "track", id: "4cOdK2wGLETKBW3PvgPWqT")
            let track = collection.tracks[0]
            print("  \(track.title) — \(track.artistLine) | album: \(track.album ?? "-") | \(track.duration ?? 0)s | cover: \(track.cover?.absoluteString ?? "-")")
            guard !track.artists.isEmpty, track.duration != nil else { throw DownlyError.message("missing fields") }
            let resolved = try await TrackResolver(ytdlp: YTDLP(tools: tools)).resolve(track)
            print("  match: \(resolved.0.title) — \(resolved.0.artists.joined(separator: ", ")) [\(resolved.0.videoID)] score \(String(format: "%.2f", resolved.1)) dur \(resolved.0.duration ?? 0)")
        }
        await soft("Spotify album") {
            let collection = try await SpotifyClient().fetch(type: "album", id: "4aawyAB9vmqN3uQ7FjRGTy")
            print("  \(collection.summary.title) by \(collection.summary.author ?? "-"): \(collection.tracks.count) tracks; first: \(collection.tracks.first?.title ?? "-") — \(collection.tracks.first?.artistLine ?? "-")")
        }
        await soft("Spotify playlist") {
            let collection = try await SpotifyClient().fetch(type: "playlist", id: "37i9dQZF1DXcBWIGoYBM5M")
            print("  \(collection.summary.title): \(collection.tracks.count) tracks; first: \(collection.tracks.first?.title ?? "-") — \(collection.tracks.first?.artistLine ?? "-")")
        }
        await soft("YouTube Music search") {
            let results = try await YouTubeMusicSearch().search("Daft Punk Get Lucky")
            for item in results.prefix(3) {
                print("  \(item.title) — \(item.artists.joined(separator: ", ")) | \(item.album ?? "-") | \(item.duration ?? 0)s | song=\(item.isSong) [\(item.videoID)]")
            }
            if results.isEmpty { throw DownlyError.message("no results") }
        }

        print("\n-- YouTube --")
        await soft("YouTube analysis") {
            let link = LinkParser.parse("https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
            guard case .video(let video) = try await analyzer.analyze(link) else { throw DownlyError.message("not a video") }
            print("  \(video.summary.title) | \(video.summary.author ?? "-") | formats: \(video.formats.count)")
            for prefs in [VideoPreferences(container: .mp4, appleCompatible: true), VideoPreferences(container: .mkv, appleCompatible: false)] {
                let choices = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: prefs, preferMuxed: false)
                print("  compat=\(prefs.appleCompatible): " + choices.map { "\($0.label)[\($0.video.id)+\($0.audio?.id ?? "-") \($0.video.codecFamily.displayName)\($0.needsTranscode ? "*" : "") \(ByteCountFormatter.string(fromByteCount: $0.estimatedBytes ?? 0, countStyle: .file))]" }.joined(separator: " "))
            }
            let best = FormatPlanner.bestAudio(video.formats, preferAAC: true)
            print("  best audio: \(best?.id ?? "-") \(best?.acodec ?? "-") \(best?.abr ?? 0)k")
        }

        print("\n-- TikTok --")
        await soft("TikTok analysis") {
            let link = LinkParser.parse("https://www.tiktok.com/@scout2015/video/6718335390845095173")!
            let analysis = try await analyzer.analyze(link)
            switch analysis {
            case .video(let video):
                let choices = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: VideoPreferences(), preferMuxed: true)
                print("  \(video.summary.title.prefix(60)) | \(video.summary.author ?? "-") | " + choices.map { "\($0.label)[\($0.video.id) \($0.video.codecFamily.displayName)]" }.joined(separator: " "))
            case .gallery(let gallery):
                print("  gallery: \(gallery.allItems.count) items")
            default:
                print("  other analysis")
            }
        }

        print("\n-- Instagram --")
        await soft("Instagram post (anonymous)") {
            let link = LinkParser.parse("https://www.instagram.com/p/BQ0eAlwhDrw/")!
            let analysis = try await analyzer.analyze(link)
            switch analysis {
            case .gallery(let gallery):
                print("  \(gallery.summary.title.prefix(60)) | \(gallery.summary.author ?? "-") | items: " + gallery.allItems.map { "\($0.kind.rawValue) \($0.resolutionLabel ?? "?")" }.joined(separator: ", "))
            case .video(let video):
                print("  video via yt-dlp: \(video.summary.title.prefix(60)) formats \(video.formats.count)")
            default:
                print("  other analysis")
            }
        }
        for code in ["Chunk8-jurw", "CDUMkliABpa", "BQ0eAlwhDrw"] {
            await soft("Instagram formats \(code)") {
                if let product = await InstagramClient(session: nil).debugProduct(shortcode: code) {
                    let medias = product["carousel_media"].array.isEmpty ? [product] : product["carousel_media"].array
                    for media in medias {
                        print("  native: has_audio=\(media["has_audio"].bool.map(String.init) ?? "nil") versions=\(media["video_versions"].array.count) dash=\(media["video_dash_manifest"].string?.count ?? 0) codec=\(media["video_codec"].string ?? "-")")
                    }
                } else {
                    print("  native: no product")
                }
                let json = try await YTDLP(tools: tools).extractInfo("https://www.instagram.com/p/\(code)/", playlist: true, useCookies: false, flat: false, extra: ["--no-flat-playlist"])
                let entries = json["entries"].array.isEmpty ? [json] : json["entries"].array
                for entry in entries {
                    let formats = entry["formats"].array.map { "\($0["format_id"].string ?? "?"):\($0["vcodec"].string ?? "nil")/\($0["acodec"].string ?? "nil")" }
                    print("  yt-dlp: \(formats.joined(separator: " "))")
                }
            }
        }
        await soft("Instagram profile (anonymous)") {
            let link = LinkParser.parse("https://www.instagram.com/instagram/")!
            guard case .gallery(let gallery) = try await analyzer.analyze(link) else { throw DownlyError.message("not a gallery") }
            print("  \(gallery.summary.title) | \(gallery.summary.author ?? "-") | pfp: \(gallery.allItems.first?.url.absoluteString.prefix(80) ?? "-")")
        }

        if downloadTests {
            print("\n-- Downloads --")
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("downly-selftest-\(UUID().uuidString)")
            let context = DownloadContext(tools: tools, settings: EngineSettings(), destination: destination, embedMetadata: true, filenameStyle: .title)
            let engine = DownloadEngine(context: context)
            let mediaTools = MediaTools(tools: tools)
            let tiktok = LinkParser.parse("https://www.tiktok.com/@scout2015/video/6718335390845095173")!

            await soft("Download TikTok video with sound") {
                guard case .video(let video) = try await analyzer.analyze(tiktok) else { throw DownlyError.message("not a video") }
                let choices = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: VideoPreferences(), preferMuxed: true)
                guard let choice = choices.first else { throw DownlyError.message("no choices") }
                let job = DownloadJob(title: video.summary.title, subtitle: "", detail: choice.label, thumbnail: nil, platform: .tiktok, kind: .video(url: video.sourceURL, selector: choice.selector, sort: nil, container: .mp4, appleCompatible: true, expectedSizes: [:]))
                let output = try await engine.run(job) { _ in }
                let info = await mediaTools.probe(output.files[0])
                print("  file: \(output.files[0].lastPathComponent) video=\(info?.videoCodec ?? "-")/\(info?.videoTag ?? "-") audio=\(info?.audioCodec ?? "-") \(info?.width ?? 0)x\(info?.height ?? 0)")
                if info?.audioCodec == nil { throw DownlyError.message("NO AUDIO STREAM") }
            }
            await soft("Extract TikTok sound as MP3 with cover") {
                guard case .video(let video) = try await analyzer.analyze(tiktok) else { throw DownlyError.message("not a video") }
                let job = DownloadJob(title: video.summary.title, subtitle: "", detail: "MP3", thumbnail: nil, platform: .tiktok, kind: .audio(url: video.sourceURL, format: .mp3, squareCover: true))
                let output = try await engine.run(job) { _ in }
                let result = try await ProcessRunner.run(tools.ffprobe, ["-v", "quiet", "-show_entries", "stream=codec_name,codec_type:format_tags=title,artist", "-of", "compact", output.files[0].path])
                print("  file: \(output.files[0].lastPathComponent)")
                print("  " + result.stdout.split(separator: "\n").joined(separator: " | "))
            }
            await soft("Tag MP3 with Spotify cover & metadata") {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("downly-tag-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let source = work.appendingPathComponent("raw.mp3")
                let generated = try await ProcessRunner.run(tools.ffmpeg, ["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:a", "libmp3lame", "-b:a", "192k", source.path])
                guard generated.succeeded else { throw DownlyError.message("ffmpeg sine failed: \(generated.stderr.suffix(200))") }
                let collection = try await SpotifyClient().fetch(type: "track", id: "4cOdK2wGLETKBW3PvgPWqT")
                let track = await SpotifyClient().enrich(collection.tracks[0])
                let cover = work.appendingPathComponent("cover.jpg")
                if let url = track.cover {
                    try await FileDownloader.download(url, to: cover)
                }
                let tags = TrackTags(title: track.title, artist: track.artistLine, albumArtist: track.artists.first, album: track.album, date: track.releaseDate.map { String($0.prefix(10)) }, track: "1", cover: track.cover)
                let tagged = try await mediaTools.tagAudio(source, tags: tags, coverFile: cover, outputName: "\(track.artists.first ?? "") - \(track.title)")
                let result = try await ProcessRunner.run(tools.ffprobe, ["-v", "quiet", "-show_entries", "stream=codec_name,codec_type:stream_disposition=attached_pic:format_tags", "-of", "compact", tagged.path])
                print("  file: \(tagged.lastPathComponent)")
                print("  " + result.stdout.split(separator: "\n").joined(separator: " | "))
                guard result.stdout.contains("attached_pic=1") else { throw DownlyError.message("cover not embedded") }
            }
            await soft("Convert VP9 to QuickTime-ready HEVC") {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("downly-vp9-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let source = work.appendingPathComponent("clip.webm")
                let generated = try await ProcessRunner.run(tools.ffmpeg, ["-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30", "-f", "lavfi", "-i", "sine=frequency=330:sample_rate=48000", "-t", "4", "-c:v", "libvpx-vp9", "-b:v", "2M", "-deadline", "realtime", "-cpu-used", "8", "-c:a", "libopus", "-shortest", source.path])
                guard generated.succeeded else { throw DownlyError.message("ffmpeg vp9 failed: \(generated.stderr.suffix(300))") }
                let start = Date()
                let converted = try await mediaTools.makeAppleCompatible(source) { _ in }
                let info = await mediaTools.probe(converted)
                print(String(format: "  converted in %.1fs → %@ video=%@/%@ audio=%@", Date().timeIntervalSince(start), converted.lastPathComponent, info?.videoCodec ?? "-", info?.videoTag ?? "-", info?.audioCodec ?? "-"))
                guard info?.videoCodec == "hevc" || info?.videoCodec == "h264", info?.audioCodec == "aac" else { throw DownlyError.message("unexpected codecs") }
            }
            await soft("Download Instagram carousel") {
                let link = LinkParser.parse("https://www.instagram.com/p/BQ0eAlwhDrw/")!
                guard case .gallery(let gallery) = try await analyzer.analyze(link) else { throw DownlyError.message("not a gallery") }
                let job = DownloadJob(title: gallery.summary.title, subtitle: "", detail: "", thumbnail: nil, platform: .instagram, kind: .gallery(items: gallery.allItems, folder: gallery.folderName))
                let output = try await engine.run(job) { _ in }
                for file in output.files {
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let info = await mediaTools.probe(file)
                    print("  \(file.lastPathComponent) \(size / 1024) KB video=\(info?.videoCodec ?? "-") audio=\(info?.audioCodec ?? "-")")
                }
            }
            await soft("Merge separate video + audio streams (Vimeo)") {
                let link = LinkParser.parse("https://vimeo.com/76979871")!
                guard case .video(let video) = try await analyzer.analyze(link) else { throw DownlyError.message("not a video") }
                let choices = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: VideoPreferences(), preferMuxed: false)
                print("  " + choices.map { "\($0.label)[\($0.video.id)+\($0.audio?.id ?? "-")]" }.joined(separator: " "))
                guard let choice = choices.first(where: { $0.tier <= 540 }) ?? choices.last else { throw DownlyError.message("no choices") }
                let job = DownloadJob(title: video.summary.title, subtitle: "", detail: choice.label, thumbnail: nil, platform: .web, kind: .video(url: video.sourceURL, selector: choice.selector, sort: nil, container: .mp4, appleCompatible: true, expectedSizes: [:]))
                let output = try await engine.run(job) { _ in }
                let info = await mediaTools.probe(output.files[0])
                print("  file: \(output.files[0].lastPathComponent) video=\(info?.videoCodec ?? "-") audio=\(info?.audioCodec ?? "-") \(info?.width ?? 0)x\(info?.height ?? 0)")
                if info?.audioCodec == nil { throw DownlyError.message("NO AUDIO STREAM") }
            }
            await soft("Download Instagram reel with sound") {
                let link = LinkParser.parse("https://www.instagram.com/reel/Chunk8-jurw/")!
                let analysis = try await analyzer.analyze(link)
                let job: DownloadJob
                switch analysis {
                case .gallery(let gallery):
                    job = DownloadJob(title: gallery.summary.title, subtitle: "", detail: "", thumbnail: nil, platform: .instagram, kind: .gallery(items: gallery.allItems, folder: gallery.folderName))
                case .video(let video):
                    let choice = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: VideoPreferences(), preferMuxed: true).first
                    job = DownloadJob(title: video.summary.title, subtitle: "", detail: "", thumbnail: nil, platform: .instagram, kind: .video(url: video.sourceURL, selector: choice?.selector ?? "bv*+ba/b", sort: nil, container: .mp4, appleCompatible: true, expectedSizes: [:]))
                default:
                    throw DownlyError.message("unexpected analysis")
                }
                let output = try await engine.run(job) { _ in }
                for file in output.files {
                    let info = await mediaTools.probe(file)
                    print("  \(file.lastPathComponent) video=\(info?.videoCodec ?? "-") audio=\(info?.audioCodec ?? "-") \(info?.width ?? 0)x\(info?.height ?? 0)")
                }
            }
            await soft("Download YouTube 360p with sound") {
                let link = LinkParser.parse("https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
                guard case .video(let video) = try await analyzer.analyze(link) else { throw DownlyError.message("not a video") }
                let choices = FormatPlanner.videoChoices(formats: video.formats, duration: video.summary.duration, preferences: VideoPreferences(), preferMuxed: false)
                guard let choice = choices.first(where: { $0.tier == 360 }) ?? choices.last else { throw DownlyError.message("no choices") }
                let job = DownloadJob(title: video.summary.title, subtitle: "", detail: choice.label, thumbnail: nil, platform: .youtube, kind: .video(url: video.sourceURL, selector: choice.selector, sort: nil, container: .mp4, appleCompatible: true, expectedSizes: [:]))
                let output = try await engine.run(job) { _ in }
                let info = await mediaTools.probe(output.files[0])
                print("  file: \(output.files[0].lastPathComponent) video=\(info?.videoCodec ?? "-") audio=\(info?.audioCodec ?? "-")")
                if info?.audioCodec == nil { throw DownlyError.message("NO AUDIO STREAM") }
            }
            try? FileManager.default.removeItem(at: destination)
        }
        finish()
    }

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            print("✓ \(name)")
        } else {
            print("✗ \(name)")
            failures.append(name)
        }
    }

    static func soft(_ name: String, _ body: () async throws -> Void) async {
        let start = Date()
        do {
            try await body()
            print(String(format: "✓ %@ (%.1fs)", name, Date().timeIntervalSince(start)))
        } catch {
            print(String(format: "⚠︎ %@ failed (%.1fs): %@", name, Date().timeIntervalSince(start), error.friendlyMessage))
            warnings.append("\(name): \(error.friendlyMessage)")
        }
    }

    static func finish() {
        print("\n== Summary ==")
        print("failures: \(failures.count), warnings: \(warnings.count)")
        for warning in warnings {
            print("  warning: \(warning)")
        }
        for failure in failures {
            print("  failure: \(failure)")
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}
