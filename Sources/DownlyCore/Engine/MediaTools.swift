import Foundation

public struct ProbeInfo: Sendable {
    public var duration: Double?
    public var videoCodec: String?
    public var videoTag: String?
    public var audioCodec: String?
    public var width: Int?
    public var height: Int?
    public var pixelFormat: String?
    public var frameRate: Double?
    public var bitRate: Double?
}

public struct TrackTags: Sendable {
    public var title: String
    public var artist: String
    public var albumArtist: String?
    public var album: String?
    public var date: String?
    public var track: String?
    public var cover: URL?

    public init(title: String, artist: String, albumArtist: String? = nil, album: String? = nil, date: String? = nil, track: String? = nil, cover: URL? = nil) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.date = date
        self.track = track
        self.cover = cover
    }
}

public actor EncoderCatalog {
    public static let shared = EncoderCatalog()
    private var cache: [String: Set<String>] = [:]

    public func encoders(ffmpeg: URL) async -> Set<String> {
        if let cached = cache[ffmpeg.path] { return cached }
        guard let result = try? await ProcessRunner.output(ffmpeg, ["-hide_banner", "-encoders"], timeout: 20) else { return [] }
        var names = Set<String>()
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0].count == 6 {
                names.insert(String(parts[1]))
            }
        }
        cache[ffmpeg.path] = names
        return names
    }
}

public struct MediaTools: Sendable {
    public let tools: ToolPaths

    public init(tools: ToolPaths) {
        self.tools = tools
    }

    public func probe(_ file: URL) async -> ProbeInfo? {
        guard let result = try? await ProcessRunner.output(tools.ffprobe, ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", file.path], timeout: 60), result.succeeded else {
            return nil
        }
        let json = J(string: result.stdout)
        var info = ProbeInfo()
        info.duration = json["format"]["duration"].double
        info.bitRate = json["format"]["bit_rate"].double
        for stream in json["streams"].array {
            let type = stream["codec_type"].string
            if type == "video", stream["disposition"]["attached_pic"].int != 1, info.videoCodec == nil {
                info.videoCodec = stream["codec_name"].string
                info.videoTag = stream["codec_tag_string"].string
                info.width = stream["width"].int
                info.height = stream["height"].int
                info.pixelFormat = stream["pix_fmt"].string
                if let rate = stream["avg_frame_rate"].string ?? stream["r_frame_rate"].string {
                    let parts = rate.split(separator: "/")
                    if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d > 0 {
                        info.frameRate = n / d
                    }
                }
            } else if type == "audio", info.audioCodec == nil {
                info.audioCodec = stream["codec_name"].string
            }
        }
        return info
    }

    public func makeAppleCompatible(_ file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let info = await probe(file), let codec = info.videoCodec?.lowercased() else { return file }
        if codec == "h264" {
            return file
        }
        if codec == "hevc" {
            if info.videoTag?.lowercased() == "hvc1" && file.pathExtension.lowercased() == "mp4" { return file }
            return try await remuxHEVC(file, info: info)
        }
        let encoders = await EncoderCatalog.shared.encoders(ffmpeg: tools.ffmpeg)
        let tier = FormatPlanner.snap(max(min(info.width ?? 1920, info.height ?? 1080), Int(Double(max(info.width ?? 1920, info.height ?? 1080)) * 9 / 16)))
        let fps = info.frameRate ?? 30
        var megabits: Double
        switch tier {
        case 4320...: megabits = 60
        case 2880..<4320: megabits = 45
        case 2160..<2880: megabits = 28
        case 1440..<2160: megabits = 14
        case 1080..<1440: megabits = 8
        default: megabits = 5
        }
        if fps > 40 { megabits *= 1.45 }
        if let sourceBitrate = info.bitRate {
            megabits = min(megabits, max(sourceBitrate / 1_000_000 * 1.6, megabits * 0.5))
        }
        let bitrate = "\(Int(megabits * 1000))k"
        let tenBit = info.pixelFormat?.contains("10") == true
        var attempts: [[String]] = []
        if encoders.contains("hevc_videotoolbox") {
            attempts.append(["-c:v", "hevc_videotoolbox", "-b:v", bitrate, "-tag:v", "hvc1"] + (tenBit ? ["-profile:v", "main10", "-pix_fmt", "p010le"] : ["-pix_fmt", "yuv420p"]))
        }
        if encoders.contains("h264_videotoolbox") && tier <= 2160 {
            attempts.append(["-c:v", "h264_videotoolbox", "-b:v", bitrate, "-pix_fmt", "yuv420p", "-profile:v", "high"])
        }
        if encoders.contains("libx265") {
            attempts.append(["-c:v", "libx265", "-preset", "faster", "-crf", "21", "-tag:v", "hvc1", "-pix_fmt", tenBit ? "yuv420p10le" : "yuv420p"])
        }
        if encoders.contains("libx264") {
            attempts.append(["-c:v", "libx264", "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p"])
        }
        if attempts.isEmpty {
            attempts.append(["-c:v", "libx264", "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p"])
        }
        let audioArgs: [String] = (info.audioCodec == "aac" || info.audioCodec == nil) ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        let output = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".apple.mp4")
        var lastError: Error = DownlyError.toolFailed("Couldn’t convert the video for QuickTime.")
        for videoArgs in attempts {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: output)
            var args = ["-hide_banner", "-nostdin", "-y", "-i", file.path, "-map", "0:v:0", "-map", "0:a?", "-map_metadata", "0"]
            args += videoArgs + audioArgs
            args += ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
            do {
                try await runFFmpeg(args, duration: info.duration, progress: progress)
                try? FileManager.default.removeItem(at: file)
                let final = file.deletingPathExtension().appendingPathExtension("mp4")
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: output, to: final)
                return final
            } catch {
                if error.isCancellation { throw error }
                lastError = error
            }
        }
        try? FileManager.default.removeItem(at: output)
        throw lastError
    }

    func remuxHEVC(_ file: URL, info: ProbeInfo) async throws -> URL {
        let output = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".remux.mp4")
        let audioArgs: [String] = (info.audioCodec == "aac" || info.audioCodec == nil || info.audioCodec == "mp3") ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        let args = ["-hide_banner", "-nostdin", "-y", "-i", file.path, "-map", "0:v:0", "-map", "0:a?", "-c:v", "copy", "-tag:v", "hvc1"] + audioArgs + ["-movflags", "+faststart", output.path]
        let result = try await ProcessRunner.run(tools.ffmpeg, args)
        guard result.succeeded else {
            try? FileManager.default.removeItem(at: output)
            return file
        }
        try? FileManager.default.removeItem(at: file)
        let final = file.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: output, to: final)
        return final
    }

    func runFFmpeg(_ args: [String], duration: Double?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let throttle = ProgressThrottle(interval: 0.2)
        let result = try await ProcessRunner.run(tools.ffmpeg, args) { line, channel in
            guard channel == .stdout, let duration, duration > 0 else { return }
            if line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                let value = Double(line.split(separator: "=").last ?? "") ?? 0
                let fraction = min(1, max(0, value / 1_000_000 / duration))
                if throttle.shouldFire() {
                    progress(fraction)
                }
            } else if line == "progress=end" {
                progress(1)
            }
        }
        guard result.succeeded else {
            let detail = result.stderr.split(whereSeparator: \.isNewline).suffix(2).joined(separator: " ")
            throw DownlyError.toolFailed(detail.isEmpty ? "FFmpeg failed." : detail)
        }
    }

    public func tagAudio(_ file: URL, tags: TrackTags, coverFile: URL?, outputName: String) async throws -> URL {
        let ext = file.pathExtension.lowercased()
        let output = file.deletingLastPathComponent().appendingPathComponent("tagged-\(UUID().uuidString.prefix(8)).\(ext)")
        var metadata: [String] = []
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            metadata += ["-metadata", "\(key)=\(value)"]
        }
        add("title", tags.title)
        add("artist", tags.artist)
        add("album_artist", tags.albumArtist)
        add("album", tags.album)
        add("date", tags.date)
        add("track", tags.track)

        let supportsCover = ["mp3", "m4a", "flac", "mp4", "aac"].contains(ext)
        var attempts: [[String]] = []
        if supportsCover, let coverFile, FileManager.default.fileExists(atPath: coverFile.path) {
            var args = ["-hide_banner", "-nostdin", "-y", "-i", file.path, "-i", coverFile.path, "-map", "0:a:0", "-map", "1:0", "-c", "copy"]
            if ext == "mp3" {
                args += ["-id3v2_version", "3", "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)"]
            }
            args += ["-disposition:v:0", "attached_pic"]
            attempts.append(args + metadata + [output.path])
        }
        var plain = ["-hide_banner", "-nostdin", "-y", "-i", file.path, "-map", "0:a:0", "-c", "copy"]
        if ext == "mp3" {
            plain += ["-id3v2_version", "3"]
        }
        attempts.append(plain + metadata + [output.path])

        for args in attempts {
            try Task.checkCancellation()
            let result = try await ProcessRunner.run(tools.ffmpeg, args)
            if result.succeeded, FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: file)
                let final = file.deletingLastPathComponent().appendingPathComponent(FileNamer.sanitize(outputName)).appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: output, to: final)
                return final
            }
            try? FileManager.default.removeItem(at: output)
        }
        let fallback = file.deletingLastPathComponent().appendingPathComponent(FileNamer.sanitize(outputName)).appendingPathExtension(ext)
        if fallback != file {
            try? FileManager.default.removeItem(at: fallback)
            try FileManager.default.moveItem(at: file, to: fallback)
        }
        return fallback
    }

    public func convertImageToJPEG(_ file: URL) async -> URL {
        let ext = file.pathExtension.lowercased()
        guard ["webp", "heic", "avif"].contains(ext) else { return file }
        let output = file.deletingPathExtension().appendingPathExtension("jpg")
        let result = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-s", "format", "jpeg", "-s", "formatOptions", "best", file.path, "--out", output.path])
        if result?.succeeded == true, FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: file)
            return output
        }
        return file
    }
}
