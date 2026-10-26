import Foundation

public struct MediaSummary: Sendable, Hashable, Codable {
    public var title: String
    public var author: String?
    public var thumbnail: URL?
    public var duration: Double?
    public var platform: Platform
    public var webpageURL: URL

    public init(title: String, author: String? = nil, thumbnail: URL? = nil, duration: Double? = nil, platform: Platform, webpageURL: URL) {
        self.title = title
        self.author = author
        self.thumbnail = thumbnail
        self.duration = duration
        self.platform = platform
        self.webpageURL = webpageURL
    }
}

public struct MediaFormat: Sendable, Hashable {
    public var id: String
    public var ext: String?
    public var vcodec: String?
    public var acodec: String?
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    public var tbr: Double?
    public var vbr: Double?
    public var abr: Double?
    public var filesize: Int64?
    public var dynamicRange: String?
    public var protocolName: String?
    public var language: String?
    public var languagePreference: Int?
    public var note: String?
    public var hasDRM: Bool
    public var audioChannels: Int?

    public init(json: J) {
        id = json["format_id"].string ?? UUID().uuidString
        ext = json["ext"].string
        vcodec = json["vcodec"].string
        acodec = json["acodec"].string
        width = json["width"].int
        height = json["height"].int
        fps = json["fps"].double
        tbr = json["tbr"].double
        vbr = json["vbr"].double
        abr = json["abr"].double
        filesize = json["filesize"].int64 ?? json["filesize_approx"].int64
        dynamicRange = json["dynamic_range"].string
        protocolName = json["protocol"].string
        language = json["language"].string
        languagePreference = json["language_preference"].int
        note = json["format_note"].string
        audioChannels = json["audio_channels"].int
        if let drm = json["has_drm"].raw as? NSNumber {
            hasDRM = drm.boolValue
        } else {
            hasDRM = false
        }
    }

    public init(id: String, ext: String? = nil, vcodec: String? = nil, acodec: String? = nil, width: Int? = nil, height: Int? = nil, fps: Double? = nil, tbr: Double? = nil, abr: Double? = nil, filesize: Int64? = nil, dynamicRange: String? = nil, note: String? = nil) {
        self.id = id
        self.ext = ext
        self.vcodec = vcodec
        self.acodec = acodec
        self.width = width
        self.height = height
        self.fps = fps
        self.tbr = tbr
        self.vbr = nil
        self.abr = abr
        self.filesize = filesize
        self.dynamicRange = dynamicRange
        self.protocolName = nil
        self.language = nil
        self.languagePreference = nil
        self.note = note
        self.hasDRM = false
        self.audioChannels = nil
    }

    public var isStoryboard: Bool {
        ext == "mhtml" || (note?.lowercased().contains("storyboard") ?? false)
    }

    public var hasVideo: Bool {
        if isStoryboard { return false }
        if let vcodec { return vcodec != "none" }
        if width != nil || height != nil { return true }
        if acodec != nil && acodec != "none" && ext.map({ ["m4a", "mp3", "opus", "ogg", "aac", "wav", "flac", "weba"].contains($0) }) == true {
            return false
        }
        return ext.map { ["mp4", "webm", "mov", "mkv", "flv", "3gp"].contains($0) } ?? false
    }

    public var hasAudio: Bool {
        if isStoryboard { return false }
        if let acodec { return acodec != "none" }
        return true
    }

    public var isAudioOnly: Bool {
        hasAudio && !hasVideo && (acodec != nil || vcodec == "none")
    }

    public var isHDR: Bool {
        guard let range = dynamicRange?.uppercased() else { return false }
        return range != "SDR" && !range.isEmpty
    }

    public var isDRCAudio: Bool {
        id.lowercased().contains("drc") || (note?.lowercased().contains("drc") ?? false)
    }

    public var codecFamily: CodecFamily {
        CodecFamily(vcodec)
    }

    public var audioCodecFamily: AudioCodecFamily {
        AudioCodecFamily(acodec, ext: ext)
    }

    public func estimatedBytes(duration: Double?) -> Int64? {
        if let filesize, filesize > 0 { return filesize }
        guard let duration, duration > 0 else { return nil }
        if let tbr, tbr > 0 { return Int64(tbr * 1000 / 8 * duration) }
        if let vbr, vbr > 0 { return Int64(vbr * 1000 / 8 * duration) }
        if let abr, abr > 0 { return Int64(abr * 1000 / 8 * duration) }
        return nil
    }
}

public enum CodecFamily: String, Sendable, Hashable {
    case h264, hevc, vp9, av1, other

    public init(_ codec: String?) {
        let value = (codec ?? "").lowercased()
        if value.hasPrefix("avc") || value.hasPrefix("h264") || value == "h.264" {
            self = .h264
        } else if value.hasPrefix("hev") || value.hasPrefix("hvc") || value.hasPrefix("h265") || value.hasPrefix("bytevc1") || value == "h.265" {
            self = .hevc
        } else if value.hasPrefix("vp9") || value.hasPrefix("vp09") {
            self = .vp9
        } else if value.hasPrefix("av01") || value == "av1" {
            self = .av1
        } else {
            self = .other
        }
    }

    public var isAppleFriendly: Bool {
        self == .h264 || self == .hevc || self == .other
    }

    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        case .other: return "Video"
        }
    }
}

public enum AudioCodecFamily: String, Sendable, Hashable {
    case aac, opus, mp3, vorbis, flac, other

    public init(_ codec: String?, ext: String?) {
        let value = (codec ?? "").lowercased()
        if value.hasPrefix("mp4a") || value.hasPrefix("aac") || (value.isEmpty && ext == "m4a") {
            self = .aac
        } else if value.hasPrefix("opus") {
            self = .opus
        } else if value.hasPrefix("mp3") {
            self = .mp3
        } else if value.hasPrefix("vorbis") {
            self = .vorbis
        } else if value.hasPrefix("flac") {
            self = .flac
        } else {
            self = .other
        }
    }
}

public enum VideoContainer: String, Codable, Sendable, CaseIterable, Hashable {
    case mp4
    case mkv

    public var title: String {
        switch self {
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        }
    }
}

public enum AudioFormat: String, Codable, Sendable, CaseIterable, Hashable {
    case mp3
    case m4a
    case opus
    case flac
    case wav

    public var title: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .opus: return "Opus"
        case .flac: return "FLAC"
        case .wav: return "WAV"
        }
    }

    public var detail: String {
        switch self {
        case .mp3: return "320 kbps · plays everywhere"
        case .m4a: return "AAC · original quality"
        case .opus: return "Original stream"
        case .flac: return "Lossless container"
        case .wav: return "Uncompressed"
        }
    }

    public var shortDetail: String {
        switch self {
        case .mp3: return "320 kbps"
        case .m4a: return "AAC"
        case .opus: return "Original"
        case .flac: return "Lossless"
        case .wav: return "PCM"
        }
    }

    public var fileExtension: String { rawValue }

    public var supportsCoverArt: Bool {
        switch self {
        case .mp3, .m4a, .flac, .opus: return true
        case .wav: return false
        }
    }

    public var ytdlpQuality: String {
        switch self {
        case .mp3: return "320K"
        default: return "0"
        }
    }

    public var sourceSelector: String {
        switch self {
        case .m4a: return "ba[ext=m4a]/ba[acodec^=mp4a]/ba/b"
        case .opus: return "ba[acodec=opus]/ba/b"
        default: return "ba/b"
        }
    }

    public func estimatedBytes(duration: Double?, source: MediaFormat?) -> Int64? {
        guard let duration, duration > 0 else { return source?.filesize }
        switch self {
        case .mp3: return Int64(duration * 320_000 / 8)
        case .m4a, .opus: return source?.estimatedBytes(duration: duration) ?? Int64(duration * 160_000 / 8)
        case .flac: return Int64(duration * 900_000 / 8)
        case .wav: return Int64(duration * 1_411_200 / 8)
        }
    }
}

public struct VideoChoice: Identifiable, Hashable, Sendable {
    public let tier: Int
    public let label: String
    public let caption: String
    public let fps: Int?
    public let isHDR: Bool
    public let video: MediaFormat
    public let audio: MediaFormat?
    public let estimatedBytes: Int64?
    public let needsTranscode: Bool
    public let isVertical: Bool
    public let selector: String

    public var id: Int { tier }

    public var badges: [String] {
        var output: [String] = []
        if let fps, fps > 30 { output.append("\(fps) fps") }
        if isHDR { output.append("HDR") }
        return output
    }
}

public struct PlaylistEntry: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let url: String
    public let duration: Double?
    public let thumbnail: URL?
    public let author: String?
}

public struct VideoAnalysis: Sendable {
    public var summary: MediaSummary
    public var id: String
    public var sourceURL: String
    public var formats: [MediaFormat]
    public var isLive: Bool
    public var playlistURL: String?
    public var usedCookies: Bool
    public var isMusicSource: Bool

    public var hasVideo: Bool {
        formats.contains { $0.hasVideo }
    }

    public var hasAudio: Bool {
        formats.contains { $0.hasAudio }
    }
}

public struct PlaylistAnalysis: Sendable {
    public var summary: MediaSummary
    public var entries: [PlaylistEntry]
    public var usedCookies: Bool
}

public struct SpotifyTrack: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var artists: [String]
    public var album: String?
    public var durationMs: Int?
    public var cover: URL?
    public var releaseDate: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var explicit: Bool

    public init(id: String, title: String, artists: [String], album: String? = nil, durationMs: Int? = nil, cover: URL? = nil, releaseDate: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil, explicit: Bool = false) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMs = durationMs
        self.cover = cover
        self.releaseDate = releaseDate
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.explicit = explicit
    }

    public var artistLine: String {
        artists.isEmpty ? "Unknown Artist" : artists.joined(separator: ", ")
    }

    public var duration: Double? {
        durationMs.map { Double($0) / 1000 }
    }

    public var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }
}

public enum MusicCollectionKind: String, Sendable, Codable {
    case track, album, playlist, artist
}

public struct MusicCollection: Sendable {
    public var summary: MediaSummary
    public var kind: MusicCollectionKind
    public var tracks: [SpotifyTrack]
    public var totalTracks: Int?
}

public struct GalleryItem: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case photo, video, audio
    }

    public var id: String
    public var kind: Kind
    public var url: URL
    public var thumbnail: URL?
    public var width: Int?
    public var height: Int?
    public var headers: [String: String]
    public var suggestedName: String
    public var ytdlpURL: String?
    public var takenAt: Date?

    public init(id: String, kind: Kind, url: URL, thumbnail: URL? = nil, width: Int? = nil, height: Int? = nil, headers: [String: String] = [:], suggestedName: String, ytdlpURL: String? = nil, takenAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.url = url
        self.thumbnail = thumbnail
        self.width = width
        self.height = height
        self.headers = headers
        self.suggestedName = suggestedName
        self.ytdlpURL = ytdlpURL
        self.takenAt = takenAt
    }

    public var resolutionLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }
}

public struct GallerySection: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var items: [GalleryItem]

    public init(id: String, title: String, items: [GalleryItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct Gallery: Sendable {
    public var summary: MediaSummary
    public var sections: [GallerySection]
    public var folderName: String
    public var isProfile: Bool

    public var allItems: [GalleryItem] {
        sections.flatMap(\.items)
    }
}

public enum Analysis: Sendable {
    case video(VideoAnalysis)
    case playlist(PlaylistAnalysis)
    case music(MusicCollection)
    case gallery(Gallery)

    public var summary: MediaSummary {
        switch self {
        case .video(let value): return value.summary
        case .playlist(let value): return value.summary
        case .music(let value): return value.summary
        case .gallery(let value): return value.summary
        }
    }
}
