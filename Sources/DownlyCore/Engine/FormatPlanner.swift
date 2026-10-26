import Foundation

public struct VideoPreferences: Sendable, Hashable {
    public var container: VideoContainer
    public var appleCompatible: Bool
    public var preferHDR: Bool

    public init(container: VideoContainer = .mp4, appleCompatible: Bool = true, preferHDR: Bool = false) {
        self.container = container
        self.appleCompatible = appleCompatible
        self.preferHDR = preferHDR
    }
}

public enum FormatPlanner {
    public static let tiers = [4320, 2880, 2160, 1440, 1080, 720, 480, 360, 240, 144]

    public static func label(for tier: Int) -> String {
        switch tier {
        case 4320: return "8K"
        case 2880: return "5K"
        case 2160: return "4K"
        default: return "\(tier)p"
        }
    }

    public static func caption(for tier: Int) -> String {
        switch tier {
        case 4320: return "4320p"
        case 2880: return "2880p"
        case 2160: return "2160p"
        case 1440: return "Quad HD"
        case 1080: return "Full HD"
        case 720: return "HD"
        case 480: return "SD"
        default: return "Low"
        }
    }

    public static func snap(_ value: Int) -> Int {
        for tier in tiers where Double(value) >= Double(tier) * 0.85 {
            return tier
        }
        return 144
    }

    public static func tier(of format: MediaFormat) -> Int? {
        if let note = format.note, let value = TextScan.first("(\\d{3,4})p", in: note), let number = Int(value) {
            return snap(number)
        }
        if let width = format.width, let height = format.height, width > 0, height > 0 {
            let short = Double(min(width, height))
            let long = Double(max(width, height))
            return snap(Int(max(short, long * 9 / 16).rounded()))
        }
        if let height = format.height, height > 0 {
            return snap(height)
        }
        return nil
    }

    public static func videoChoices(formats: [MediaFormat], duration: Double?, preferences: VideoPreferences, preferMuxed: Bool) -> [VideoChoice] {
        let videos = formats.filter { $0.hasVideo && !$0.hasDRM && !$0.isStoryboard }
        var grouped: [Int: [MediaFormat]] = [:]
        for format in videos {
            guard let tier = tier(of: format) else { continue }
            grouped[tier, default: []].append(format)
        }
        if grouped.isEmpty, let fallback = videos.max(by: { ($0.tbr ?? 0) < ($1.tbr ?? 0) }) {
            grouped[720] = [fallback]
        }

        var choices: [VideoChoice] = []
        for (tier, candidates) in grouped {
            guard let video = pickVideo(candidates, preferences: preferences, preferMuxed: preferMuxed) else { continue }
            let audio: MediaFormat? = (video.hasAudio && video.acodec != nil) ? nil : bestAudio(formats, preferAAC: preferences.container == .mp4 || preferences.appleCompatible)
            let videoBytes = video.estimatedBytes(duration: duration)
            let audioBytes = audio?.estimatedBytes(duration: duration)
            var total: Int64?
            if let videoBytes {
                total = videoBytes + (audioBytes ?? 0)
            }
            let isVertical = (video.height ?? 0) > (video.width ?? 0)
            let needsTranscode = preferences.appleCompatible && !video.codecFamily.isAppleFriendly
            let fpsValue = video.fps.map { Int($0.rounded()) }
            choices.append(VideoChoice(
                tier: tier,
                label: label(for: tier),
                caption: caption(for: tier),
                fps: fpsValue,
                isHDR: video.isHDR,
                video: video,
                audio: audio,
                estimatedBytes: total,
                needsTranscode: needsTranscode,
                isVertical: isVertical,
                selector: selector(video: video, audio: audio, tier: tier, vertical: isVertical, preferences: preferences)
            ))
        }
        return choices.sorted { $0.tier > $1.tier }
    }

    static func pickVideo(_ candidates: [MediaFormat], preferences: VideoPreferences, preferMuxed: Bool) -> MediaFormat? {
        candidates.max { lhs, rhs in
            score(lhs, preferences: preferences, preferMuxed: preferMuxed).lexicographicallyPrecedes(score(rhs, preferences: preferences, preferMuxed: preferMuxed))
        }
    }

    static func score(_ format: MediaFormat, preferences: VideoPreferences, preferMuxed: Bool) -> [Double] {
        let hdrScore: Double = format.isHDR == preferences.preferHDR ? 1 : 0
        let codec: Double
        if preferences.appleCompatible {
            switch format.codecFamily {
            case .h264: codec = 5
            case .hevc: codec = 4.5
            case .other: codec = 4
            case .vp9: codec = 3
            case .av1: codec = 2
            }
        } else {
            switch format.codecFamily {
            case .av1: codec = 5
            case .vp9: codec = 4.5
            case .hevc: codec = 4
            case .h264: codec = 3.5
            case .other: codec = 3
            }
        }
        let fps = (format.fps ?? 30).rounded()
        let muxed: Double = (preferMuxed && format.hasAudio && format.acodec != nil) ? 1 : 0
        let proto: Double = {
            let name = format.protocolName ?? "https"
            if name.hasPrefix("http") { return 2 }
            if name.contains("dash") { return 1.5 }
            return 1
        }()
        let bitrate = format.tbr ?? format.vbr ?? Double(format.filesize ?? 0) / 1_000_000
        if preferences.appleCompatible {
            return [hdrScore, muxed, codec, fps, proto, bitrate]
        }
        return [hdrScore, muxed, fps, codec, proto, bitrate]
    }

    public static func bestAudio(_ formats: [MediaFormat], preferAAC: Bool) -> MediaFormat? {
        let audios = formats.filter { $0.isAudioOnly && !$0.hasDRM }
        return audios.max { lhs, rhs in
            audioScore(lhs, preferAAC: preferAAC).lexicographicallyPrecedes(audioScore(rhs, preferAAC: preferAAC))
        }
    }

    static func audioScore(_ format: MediaFormat, preferAAC: Bool) -> [Double] {
        let language = Double(format.languagePreference ?? 0)
        let drc: Double = format.isDRCAudio ? 0 : 1
        let codec: Double
        switch format.audioCodecFamily {
        case .aac: codec = preferAAC ? 3 : 2
        case .opus: codec = preferAAC ? 2 : 3
        case .mp3, .vorbis: codec = 1
        case .flac: codec = 1.5
        case .other: codec = 0.5
        }
        let channels = Double(min(format.audioChannels ?? 2, 2))
        let proto: Double = (format.protocolName ?? "https").hasPrefix("http") ? 1 : 0
        return [language, drc, codec, channels, proto, format.abr ?? format.tbr ?? 0]
    }

    static func selector(video: MediaFormat, audio: MediaFormat?, tier: Int, vertical: Bool, preferences: VideoPreferences) -> String {
        var parts: [String] = []
        if let audio {
            parts.append("\(video.id)+\(audio.id)")
        }
        parts.append("\(video.id)+ba")
        parts.append(video.id)
        let bound = vertical ? "width" : "height"
        let limit = vertical ? tier : Int(Double(tier) * 1.05)
        parts.append("bv*[\(bound)<=\(limit)]+ba")
        parts.append("b[\(bound)<=\(limit)]")
        parts.append("bv*+ba")
        parts.append("b")
        return parts.joined(separator: "/")
    }

    public static func playlistSelector(tier: Int?, preferences: VideoPreferences) -> (selector: String, sort: String) {
        let audioSort = preferences.container == .mp4 || preferences.appleCompatible ? "acodec:aac" : "acodec:opus"
        guard let tier else {
            let codec = preferences.appleCompatible ? ",vcodec:h264" : ""
            return ("bv*+ba/b", "res,fps\(codec),\(audioSort)")
        }
        let codec = preferences.appleCompatible ? ",vcodec:h264" : ""
        return ("bv*[height<=\(tier)]+ba/b[height<=\(tier)]/bv*+ba/b", "res:\(tier),fps\(codec),\(audioSort)")
    }
}
