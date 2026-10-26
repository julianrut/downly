import Foundation

public enum FilenameStyle: String, Codable, Sendable, CaseIterable, Hashable {
    case title
    case titleAndID
    case authorAndTitle

    public var displayName: String {
        switch self {
        case .title: return "Title"
        case .titleAndID: return "Title [ID]"
        case .authorAndTitle: return "Author – Title"
        }
    }

    var ytdlpTemplate: String {
        switch self {
        case .title: return "%(title).170B.%(ext)s"
        case .titleAndID: return "%(title).150B [%(id)s].%(ext)s"
        case .authorAndTitle: return "%(uploader,channel,creator|Unknown).60B - %(title).140B.%(ext)s"
        }
    }
}

public enum JobKind: Codable, Sendable, Hashable {
    case video(url: String, selector: String, sort: String?, container: VideoContainer, appleCompatible: Bool, expectedSizes: [String: Int64])
    case audio(url: String, format: AudioFormat, squareCover: Bool)
    case spotify(track: SpotifyTrack, format: AudioFormat, folder: String?)
    case gallery(items: [GalleryItem], folder: String?)
}

public struct DownloadJob: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var detail: String
    public var thumbnail: URL?
    public var platform: Platform
    public var kind: JobKind
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, subtitle: String, detail: String, thumbnail: URL?, platform: Platform, kind: JobKind, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.thumbnail = thumbnail
        self.platform = platform
        self.kind = kind
        self.createdAt = createdAt
    }

    public var isAudio: Bool {
        switch kind {
        case .audio, .spotify: return true
        case .video: return false
        case .gallery(let items, _): return items.allSatisfy { $0.kind == .audio }
        }
    }
}

public enum JobPhase: Sendable, Equatable {
    case preparing(String)
    case downloading
    case processing(String)
}

public struct JobProgress: Sendable {
    public var phase: JobPhase
    public var fraction: Double?
    public var speed: Double?
    public var eta: Double?
    public var downloadedBytes: Int64?
    public var totalBytes: Int64?
    public var note: String?

    public init(phase: JobPhase, fraction: Double? = nil, speed: Double? = nil, eta: Double? = nil, downloadedBytes: Int64? = nil, totalBytes: Int64? = nil, note: String? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.speed = speed
        self.eta = eta
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.note = note
    }
}

public struct JobOutput: Sendable {
    public var files: [URL]
    public var revealTarget: URL
    public var note: String?
}

public struct DownloadContext: Sendable {
    public var tools: ToolPaths
    public var settings: EngineSettings
    public var destination: URL
    public var embedMetadata: Bool
    public var filenameStyle: FilenameStyle

    public init(tools: ToolPaths, settings: EngineSettings, destination: URL, embedMetadata: Bool, filenameStyle: FilenameStyle) {
        self.tools = tools
        self.settings = settings
        self.destination = destination
        self.embedMetadata = embedMetadata
        self.filenameStyle = filenameStyle
    }
}

final class ByteAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var expected: [String: Int64]
    private var current: [String: (Int64, Int64?)] = [:]
    private var lastFraction: Double = 0

    init(expected: [String: Int64]) {
        self.expected = expected
    }

    func update(_ progress: YTDLPProgress) -> (fraction: Double?, downloaded: Int64, total: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        let key = progress.formatID ?? "default"
        var downloaded = progress.downloaded ?? current[key]?.0 ?? 0
        var total = progress.total ?? current[key]?.1
        if progress.status == "finished" {
            if let t = total { downloaded = max(downloaded, t) } else { total = downloaded }
        }
        if total == nil, let count = progress.fragmentCount, let index = progress.fragmentIndex, count > 0, downloaded > 0, index > 0 {
            total = Int64(Double(downloaded) / Double(index) * Double(count))
        }
        current[key] = (downloaded, total)
        let keys = Set(expected.keys).union(current.keys)
        var sumDownloaded: Int64 = 0
        var sumTotal: Int64 = 0
        var unknown = false
        for id in keys {
            let done = current[id]?.0 ?? 0
            let size = current[id]?.1 ?? expected[id]
            if let size, size > 0 {
                sumTotal += max(size, done)
                sumDownloaded += done
            } else if current[id] != nil {
                unknown = true
            }
        }
        guard sumTotal > 0 else { return (nil, sumDownloaded, nil) }
        var fraction = Double(sumDownloaded) / Double(sumTotal)
        if unknown { fraction *= 0.9 }
        fraction = max(lastFraction, min(fraction, 0.999))
        lastFraction = fraction
        return (fraction, sumDownloaded, sumTotal)
    }
}

public struct DownloadEngine: Sendable {
    public let context: DownloadContext

    public init(context: DownloadContext) {
        self.context = context
    }

    var ytdlp: YTDLP {
        YTDLP(tools: context.tools, cookieBrowser: context.settings.cookieBrowser)
    }

    var media: MediaTools {
        MediaTools(tools: context.tools)
    }

    func cookies(for url: String) -> Bool {
        guard context.settings.cookieBrowser != nil else { return false }
        if context.settings.alwaysUseCookies { return true }
        return url.contains("instagram.com")
    }

    public func run(_ job: DownloadJob, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> JobOutput {
        let staging = AppPaths.stagingDirectory(for: job.id)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
        switch job.kind {
        case .video(let url, let selector, let sort, let container, let appleCompatible, let expectedSizes):
            return try await runVideo(url: url, selector: selector, sort: sort, container: container, appleCompatible: appleCompatible, expected: expectedSizes, staging: staging, progress: progress)
        case .audio(let url, let format, let squareCover):
            return try await runAudio(url: url, format: format, squareCover: squareCover, staging: staging, progress: progress)
        case .spotify(let track, let format, let folder):
            return try await runSpotify(track: track, format: format, folder: folder, staging: staging, progress: progress)
        case .gallery(let items, let folder):
            return try await runGallery(items: items, folder: folder, staging: staging, progress: progress)
        }
    }

    func ytdlpRun(arguments: [String], url: String, expected: [String: Int64], progress: @escaping @Sendable (JobProgress) -> Void) async throws -> [String] {
        let aggregator = ByteAggregator(expected: expected)
        let throttle = ProgressThrottle(interval: 0.15)
        let useCookies = cookies(for: url)
        let handler: @Sendable (YTDLPEvent) -> Void = { event in
            switch event {
            case .progress(let p):
                let result = aggregator.update(p)
                if throttle.shouldFire(force: p.status == "finished") {
                    progress(JobProgress(phase: .downloading, fraction: result.fraction, speed: p.speed, eta: p.eta, downloadedBytes: result.downloaded, totalBytes: result.total))
                }
            case .postprocess(let name, let status):
                if status == "started" || status == "processing" {
                    progress(JobProgress(phase: .processing(DownloadEngine.describe(postprocessor: name))))
                }
            case .file, .log:
                break
            }
        }
        do {
            return try await ytdlp.run(arguments: arguments, url: url, useCookies: useCookies, onEvent: handler)
        } catch let error as DownlyError where error.needsAccount && !useCookies && context.settings.cookieBrowser != nil {
            return try await ytdlp.run(arguments: arguments, url: url, useCookies: true, onEvent: handler)
        }
    }

    static func describe(postprocessor name: String) -> String {
        switch name {
        case "Merger", "FFmpegMerger": return "Merging video and audio"
        case "ExtractAudio", "FFmpegExtractAudio": return "Converting audio"
        case "EmbedThumbnail": return "Adding cover art"
        case "Metadata", "FFmpegMetadata": return "Writing details"
        case "VideoRemuxer", "FFmpegVideoRemuxer": return "Finishing up"
        case "VideoConvertor", "FFmpegVideoConvertor": return "Converting video"
        case "ThumbnailsConvertor", "FFmpegThumbnailsConvertor": return "Preparing cover art"
        case "FixupM3u8", "FixupM4a", "FixupStretched", "FixupDuplicateMoov", "FixupTimestamp", "FixupDuration": return "Polishing file"
        case "MoveFiles", "MoveFilesAfterDownload": return "Finishing up"
        default: return "Processing"
        }
    }

    func outputArguments(staging: URL, template: String? = nil) -> [String] {
        ["-P", staging.path, "-o", template ?? context.filenameStyle.ytdlpTemplate, "--no-part", "--windows-filenames"]
    }

    func runVideo(url: String, selector: String, sort: String?, container: VideoContainer, appleCompatible: Bool, expected: [String: Int64], staging: URL, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> JobOutput {
        progress(JobProgress(phase: .preparing("Starting")))
        var args = ["-f", selector]
        if let sort, !sort.isEmpty {
            args += ["-S", sort]
        }
        args += ["--merge-output-format", container.rawValue, "--remux-video", container.rawValue, "--no-playlist"]
        if context.embedMetadata {
            args += ["--embed-metadata"]
        }
        args += outputArguments(staging: staging)
        let files = try await ytdlpRun(arguments: args, url: url, expected: expected, progress: progress)
        var finals: [URL] = []
        for path in files {
            var file = URL(fileURLWithPath: path)
            if appleCompatible && container == .mp4 {
                if let info = await media.probe(file), let codec = info.videoCodec?.lowercased(), codec != "h264" && !(codec == "hevc" && info.videoTag == "hvc1") {
                    progress(JobProgress(phase: .processing("Optimizing for QuickTime"), fraction: 0))
                    file = try await media.makeAppleCompatible(file) { fraction in
                        progress(JobProgress(phase: .processing("Optimizing for QuickTime"), fraction: fraction))
                    }
                }
            }
            finals.append(try FileNamer.move(file, into: context.destination))
        }
        guard let first = finals.first else { throw DownlyError.nothingToDownload }
        return JobOutput(files: finals, revealTarget: first)
    }

    func runAudio(url: String, format: AudioFormat, squareCover: Bool, staging: URL, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> JobOutput {
        progress(JobProgress(phase: .preparing("Starting")))
        var args = ["-f", format.sourceSelector, "-x", "--audio-format", format.rawValue, "--audio-quality", format.ytdlpQuality, "--no-playlist"]
        if context.embedMetadata {
            args += ["--embed-metadata"]
            if format.supportsCoverArt {
                args += ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
                if squareCover {
                    args += ["--ppa", "ThumbnailsConvertor+ffmpeg_o:-c:v mjpeg -qmin 1 -qscale:v 1 -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\""]
                }
            }
        }
        args += outputArguments(staging: staging)
        let files = try await ytdlpRun(arguments: args, url: url, expected: [:], progress: progress)
        let finals = try files.map { try FileNamer.move(URL(fileURLWithPath: $0), into: context.destination) }
        guard let first = finals.first else { throw DownlyError.nothingToDownload }
        return JobOutput(files: finals, revealTarget: first)
    }

    func runSpotify(track input: SpotifyTrack, format: AudioFormat, folder: String?, staging: URL, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> JobOutput {
        progress(JobProgress(phase: .preparing("Finding on YouTube Music")))
        let spotify = SpotifyClient()
        var track = await spotify.enrich(input)
        let resolver = TrackResolver(ytdlp: ytdlp)
        let (match, _) = try await resolver.resolve(track)
        if track.album == nil, let album = match.album, !album.isEmpty {
            track.album = album
        }
        let matchNote = "Matched “\(match.title)”" + (match.artists.isEmpty ? "" : " by \(match.artists.joined(separator: ", "))")
        progress(JobProgress(phase: .preparing("Downloading audio"), note: matchNote))

        let audioArgs = ["-f", format.sourceSelector, "-x", "--audio-format", format.rawValue, "--audio-quality", format.ytdlpQuality, "--no-playlist"]
            + outputArguments(staging: staging, template: "%(id)s.%(ext)s")
        let files = try await ytdlpRun(arguments: audioArgs, url: match.url, expected: [:], progress: { update in
            var copy = update
            copy.note = matchNote
            progress(copy)
        })
        guard let downloaded = files.first.map(URL.init(fileURLWithPath:)) else { throw DownlyError.nothingToDownload }

        progress(JobProgress(phase: .processing("Adding cover art & tags"), note: matchNote))
        var coverFile: URL?
        if format.supportsCoverArt, let cover = track.cover {
            let target = staging.appendingPathComponent("cover.jpg")
            if (try? await FileDownloader.download(cover, to: target)) != nil {
                coverFile = target
            }
        }
        var trackNumber: String?
        if let number = track.trackNumber {
            trackNumber = String(number)
        }
        let tags = TrackTags(
            title: track.title,
            artist: track.artists.joined(separator: ", "),
            albumArtist: track.artists.first,
            album: track.album,
            date: track.releaseDate.map { String($0.prefix(10)) },
            track: trackNumber,
            cover: track.cover
        )
        let name = "\(track.artists.first ?? "Unknown Artist") - \(track.title)"
        let tagged = try await media.tagAudio(downloaded, tags: tags, coverFile: coverFile, outputName: name)
        var directory = context.destination
        if let folder, !folder.isEmpty {
            directory = context.destination.appendingPathComponent(FileNamer.sanitize(folder), isDirectory: true)
        }
        let final = try FileNamer.move(tagged, into: directory, name: name)
        return JobOutput(files: [final], revealTarget: final, note: matchNote)
    }

    func runGallery(items: [GalleryItem], folder: String?, staging: URL, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> JobOutput {
        guard !items.isEmpty else { throw DownlyError.nothingToDownload }
        var directory = context.destination
        if items.count > 1, let folder, !folder.isEmpty {
            directory = FileNamer.uniqueDirectory(in: context.destination, name: FileNamer.sanitize(folder))
        }
        var finals: [URL] = []
        let count = Double(items.count)
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let base = Double(index) / count
            progress(JobProgress(phase: .downloading, fraction: base, note: items.count > 1 ? "Item \(index + 1) of \(items.count)" : nil))
            var produced: URL?
            if item.kind == .video, let source = item.ytdlpURL {
                var args = ["-f", "bv*+ba/b", "-S", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4", "--remux-video", "mp4"]
                if let position = item.playlistIndex {
                    args += ["--yes-playlist", "--playlist-items", String(position)]
                } else {
                    args += ["--no-playlist"]
                }
                args += outputArguments(staging: staging, template: "\(FileNamer.sanitize(item.suggestedName)).%(ext)s")
                let itemNote: String? = items.count > 1 ? "Item \(index + 1) of \(items.count)" : nil
                if let files = try? await ytdlpRun(arguments: args, url: source, expected: [:], progress: { update in
                    var copy = update
                    copy.fraction = base + (update.fraction ?? 0) / count
                    copy.note = itemNote
                    progress(copy)
                }), let first = files.first {
                    produced = URL(fileURLWithPath: first)
                }
            }
            if produced == nil {
                produced = try await downloadDirect(item, staging: staging) { fraction, received, expected in
                    progress(JobProgress(phase: .downloading, fraction: base + fraction / count, downloadedBytes: received, totalBytes: expected, note: items.count > 1 ? "Item \(index + 1) of \(items.count)" : nil))
                }
            }
            guard var file = produced else { continue }
            if file.pathExtension.lowercased() == "webp" {
                file = await media.convertImageToJPEG(file)
            }
            finals.append(try FileNamer.move(file, into: directory, name: item.suggestedName))
        }
        guard let first = finals.first else { throw DownlyError.nothingToDownload }
        return JobOutput(files: finals, revealTarget: finals.count > 1 ? directory : first)
    }

    func downloadDirect(_ item: GalleryItem, staging: URL, progress: @escaping @Sendable (Double, Int64, Int64?) -> Void) async throws -> URL {
        let temp = staging.appendingPathComponent("item-\(UUID().uuidString)")
        let throttle = ProgressThrottle(interval: 0.15)
        let response = try await FileDownloader.download(item.url, to: temp, headers: item.headers) { received, expected in
            if throttle.shouldFire() {
                let fraction = expected.map { Double(received) / Double(max($0, 1)) } ?? 0
                progress(min(fraction, 1), received, expected)
            }
        }
        let ext = DownloadEngine.fileExtension(for: item, mime: response?.mimeType)
        let named = staging.appendingPathComponent(FileNamer.sanitize(item.suggestedName)).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.moveItem(at: temp, to: named)
        return named
    }

    static func fileExtension(for item: GalleryItem, mime: String?) -> String {
        if let mime = mime?.lowercased() {
            switch mime {
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/png": return "png"
            case "image/webp": return "webp"
            case "image/heic", "image/heif": return "heic"
            case "image/avif": return "avif"
            case "image/gif": return "gif"
            case "video/mp4": return "mp4"
            case "video/quicktime": return "mov"
            case "video/webm": return "webm"
            case "audio/mpeg", "audio/mp3": return "mp3"
            case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
            default: break
            }
        }
        let pathExt = item.url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic", "mp4", "mov", "mp3", "m4a", "gif"].contains(pathExt) {
            return pathExt == "jpeg" ? "jpg" : pathExt
        }
        switch item.kind {
        case .photo: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        }
    }
}
