import Foundation

public enum Platform: String, Codable, Sendable, CaseIterable, Hashable {
    case youtube
    case spotify
    case instagram
    case tiktok
    case web

    public var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .web: return "Web"
        }
    }
}

public enum LinkKind: Equatable, Sendable, Hashable {
    case youtubeVideo(id: String)
    case youtubePlaylist(id: String)
    case youtubeOther
    case spotifyTrack(id: String)
    case spotifyAlbum(id: String)
    case spotifyPlaylist(id: String)
    case spotifyArtist(id: String)
    case spotifyShort
    case instagramPost(shortcode: String)
    case instagramStory(username: String, storyID: String?)
    case instagramHighlight(id: String)
    case instagramProfile(username: String)
    case instagramShare
    case tiktokVideo(id: String)
    case tiktokPhoto(id: String)
    case tiktokShort
    case tiktokOther
    case generic
}

public struct ParsedLink: Equatable, Sendable, Hashable {
    public let url: URL
    public let platform: Platform
    public let kind: LinkKind
    public let playlistID: String?
    public let isMusic: Bool

    public init(url: URL, platform: Platform, kind: LinkKind, playlistID: String? = nil, isMusic: Bool = false) {
        self.url = url
        self.platform = platform
        self.kind = kind
        self.playlistID = playlistID
        self.isMusic = isMusic
    }

    public var needsResolution: Bool {
        switch kind {
        case .spotifyShort, .tiktokShort, .instagramShare: return true
        default: return false
        }
    }
}

public enum LinkParser {
    private static let instagramReserved: Set<String> = [
        "explore", "accounts", "direct", "about", "developer", "legal", "privacy", "terms", "web", "reels", "reel", "p", "tv",
        "stories", "challenge", "emails", "session", "settings", "api", "graphql", "static", "ar", "s", "share", "your_activity",
        "nametag", "topics", "locations", "tags", "directory", "press", "help", "oauth", "data", "download",
    ]

    public static func firstLink(in text: String) -> ParsedLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = parse(trimmed) {
            return direct
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in detector.matches(in: trimmed, options: [], range: range) {
            if let url = match.url, let parsed = parse(url.absoluteString) {
                return parsed
            }
        }
        return nil
    }

    public static func parse(_ raw: String) -> ParsedLink? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("spotify:") {
            let parts = text.split(separator: ":").map(String.init)
            if parts.count >= 3, let url = URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])") {
                return parseURL(url)
            }
            return nil
        }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            guard text.contains("."), !text.hasPrefix(".") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, host.contains(".") else { return nil }
        return parseURL(url)
    }

    public static func parseURL(_ url: URL) -> ParsedLink? {
        guard let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = url.path
        let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        let query = queryItems(url)

        if host == "youtu.be" {
            guard let id = segments.first else { return nil }
            return ParsedLink(url: canonicalYouTube(id), platform: .youtube, kind: .youtubeVideo(id: id), playlistID: query["list"])
        }
        if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            let isMusic = host.hasPrefix("music.")
            if let id = query["v"], !id.isEmpty {
                return ParsedLink(url: canonicalYouTube(id), platform: .youtube, kind: .youtubeVideo(id: id), playlistID: query["list"], isMusic: isMusic)
            }
            if let first = segments.first, ["shorts", "live", "embed", "v", "e"].contains(first), segments.count > 1 {
                let id = segments[1]
                return ParsedLink(url: canonicalYouTube(id), platform: .youtube, kind: .youtubeVideo(id: id), isMusic: isMusic)
            }
            if segments.first == "playlist", let list = query["list"] {
                let canonical = URL(string: "https://www.youtube.com/playlist?list=\(list)") ?? url
                return ParsedLink(url: canonical, platform: .youtube, kind: .youtubePlaylist(id: list), playlistID: list, isMusic: isMusic)
            }
            if segments.isEmpty { return nil }
            return ParsedLink(url: url, platform: .youtube, kind: .youtubeOther, isMusic: isMusic)
        }

        if host == "spotify.link" || host == "spotify.app.link" {
            return ParsedLink(url: url, platform: .spotify, kind: .spotifyShort)
        }
        if host.hasSuffix("spotify.com") {
            var parts = segments
            if let first = parts.first, first.hasPrefix("intl-") {
                parts.removeFirst()
            }
            if parts.first == "embed" {
                parts.removeFirst()
            }
            guard parts.count >= 2 else { return nil }
            let type = parts[0]
            let id = parts[1]
            let canonical = URL(string: "https://open.spotify.com/\(type)/\(id)") ?? url
            switch type {
            case "track": return ParsedLink(url: canonical, platform: .spotify, kind: .spotifyTrack(id: id), isMusic: true)
            case "album": return ParsedLink(url: canonical, platform: .spotify, kind: .spotifyAlbum(id: id), isMusic: true)
            case "playlist": return ParsedLink(url: canonical, platform: .spotify, kind: .spotifyPlaylist(id: id), isMusic: true)
            case "artist": return ParsedLink(url: canonical, platform: .spotify, kind: .spotifyArtist(id: id), isMusic: true)
            default: return nil
            }
        }

        if host == "instagr.am" || host.hasSuffix("instagram.com") {
            var parts = segments
            if parts.count >= 3, ["p", "reel", "reels", "tv"].contains(parts[1]), !["p", "reel", "reels", "tv", "stories"].contains(parts[0]) {
                parts.removeFirst()
            }
            guard let first = parts.first else { return nil }
            switch first {
            case "p", "reel", "reels", "tv":
                guard parts.count >= 2 else { return nil }
                let code = parts[1]
                let canonical = URL(string: "https://www.instagram.com/\(first == "reels" ? "reel" : first)/\(code)/") ?? url
                return ParsedLink(url: canonical, platform: .instagram, kind: .instagramPost(shortcode: code))
            case "stories":
                guard parts.count >= 2 else { return nil }
                if parts[1] == "highlights" {
                    guard parts.count >= 3 else { return nil }
                    return ParsedLink(url: url, platform: .instagram, kind: .instagramHighlight(id: parts[2]))
                }
                let story = parts.count >= 3 ? parts[2] : nil
                return ParsedLink(url: url, platform: .instagram, kind: .instagramStory(username: parts[1], storyID: story))
            case "s":
                if parts.count >= 2, let decoded = decodeHighlightShare(parts[1]) {
                    return ParsedLink(url: url, platform: .instagram, kind: .instagramHighlight(id: decoded))
                }
                return ParsedLink(url: url, platform: .instagram, kind: .instagramShare)
            case "share":
                return ParsedLink(url: url, platform: .instagram, kind: .instagramShare)
            default:
                guard !instagramReserved.contains(first.lowercased()), isInstagramUsername(first) else { return nil }
                let canonical = URL(string: "https://www.instagram.com/\(first)/") ?? url
                return ParsedLink(url: canonical, platform: .instagram, kind: .instagramProfile(username: first))
            }
        }

        if host == "vm.tiktok.com" || host == "vt.tiktok.com" {
            return ParsedLink(url: url, platform: .tiktok, kind: .tiktokShort)
        }
        if host.hasSuffix("tiktok.com") {
            if segments.first == "t" {
                return ParsedLink(url: url, platform: .tiktok, kind: .tiktokShort)
            }
            if let index = segments.firstIndex(of: "video"), index + 1 < segments.count {
                let id = segments[index + 1]
                return ParsedLink(url: url, platform: .tiktok, kind: .tiktokVideo(id: id))
            }
            if let index = segments.firstIndex(of: "photo"), index + 1 < segments.count {
                let id = segments[index + 1]
                return ParsedLink(url: url, platform: .tiktok, kind: .tiktokPhoto(id: id))
            }
            if segments.first == "v", segments.count > 1 {
                let id = segments[1].replacingOccurrences(of: ".html", with: "")
                return ParsedLink(url: url, platform: .tiktok, kind: .tiktokVideo(id: id))
            }
            if segments.isEmpty { return nil }
            return ParsedLink(url: url, platform: .tiktok, kind: .tiktokOther)
        }

        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        return ParsedLink(url: url, platform: .web, kind: .generic)
    }

    public static func canonicalYouTube(_ id: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }

    static func queryItems(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            if let value = item.value, result[item.name] == nil {
                result[item.name] = value
            }
        }
        return result
    }

    static func isInstagramUsername(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 30 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func decodeHighlightShare(_ token: String) -> String? {
        var base = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 {
            base += "="
        }
        guard let data = Data(base64Encoded: base), let text = String(data: data, encoding: .utf8) else { return nil }
        guard text.hasPrefix("highlight:") else { return nil }
        return String(text.dropFirst("highlight:".count))
    }
}
