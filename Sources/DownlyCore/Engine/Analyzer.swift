import Foundation

public struct EngineSettings: Sendable, Hashable {
    public var cookieBrowser: CookieBrowser?
    public var alwaysUseCookies: Bool

    public init(cookieBrowser: CookieBrowser? = nil, alwaysUseCookies: Bool = false) {
        self.cookieBrowser = cookieBrowser
        self.alwaysUseCookies = alwaysUseCookies
    }
}

public struct Analyzer: Sendable {
    public let tools: ToolPaths
    public let settings: EngineSettings

    public init(tools: ToolPaths, settings: EngineSettings) {
        self.tools = tools
        self.settings = settings
    }

    var ytdlp: YTDLP {
        YTDLP(tools: tools, cookieBrowser: settings.cookieBrowser)
    }

    public func resolve(_ link: ParsedLink) async -> ParsedLink {
        guard link.needsResolution else { return link }
        let http = HTTPClient(userAgent: UserAgent.safari)
        let final: URL
        switch link.kind {
        case .spotifyShort:
            final = await SpotifyClient(http: http).resolveShortLink(link.url)
        default:
            final = await http.finalURL(for: link.url)
        }
        if let parsed = LinkParser.parseURL(final), !parsed.needsResolution {
            return parsed
        }
        return link
    }

    public func analyze(_ input: ParsedLink) async throws -> Analysis {
        let link = await resolve(input)
        switch link.kind {
        case .youtubeVideo:
            return try await analyzeVideo(link)
        case .youtubePlaylist, .youtubeOther:
            return try await analyzeAny(link)
        case .spotifyTrack(let id):
            return .music(try await SpotifyClient().fetch(type: "track", id: id))
        case .spotifyAlbum(let id):
            return .music(try await SpotifyClient().fetch(type: "album", id: id))
        case .spotifyPlaylist(let id):
            return .music(try await SpotifyClient().fetch(type: "playlist", id: id))
        case .spotifyArtist(let id):
            return .music(try await SpotifyClient().fetch(type: "artist", id: id))
        case .spotifyShort:
            throw DownlyError.unavailable("Couldn’t open this Spotify short link.")
        case .instagramPost(let shortcode):
            return try await analyzeInstagramPost(link, shortcode: shortcode)
        case .instagramStory(let username, let storyID):
            if username == "highlights", let storyID {
                return .gallery(try await instagramClient().highlight(id: storyID, url: link.url))
            }
            return .gallery(try await instagramClient().stories(username: username, storyID: storyID, url: link.url))
        case .instagramHighlight(let id):
            return .gallery(try await instagramClient().highlight(id: id, url: link.url))
        case .instagramProfile(let username):
            return .gallery(try await instagramClient().profileGallery(username: username, url: link.url))
        case .instagramShare:
            return try await analyzeAny(link)
        case .tiktokPhoto(let id):
            return try await analyzeTikTokPhoto(link, id: id)
        case .tiktokVideo(let id):
            do {
                let analysis = try await analyzeVideo(link)
                if case .video(let video) = analysis, !video.hasVideo, let gallery = try? await TikTokClient().photoPost(url: link.url, id: id) {
                    return .gallery(gallery)
                }
                return analysis
            } catch {
                if error.isCancellation { throw error }
                if let gallery = try? await TikTokClient().photoPost(url: link.url, id: id) {
                    return .gallery(gallery)
                }
                throw error
            }
        case .tiktokShort, .tiktokOther, .generic:
            return try await analyzeAny(link)
        }
    }

    func instagramClient() async -> InstagramClient {
        guard let browser = settings.cookieBrowser else { return InstagramClient(session: nil) }
        let snapshot = try? await BrowserCookies.shared.snapshot(for: browser, ytdlp: tools.ytdlp)
        return InstagramClient(session: snapshot)
    }

    func analyzeInstagramPost(_ link: ParsedLink, shortcode: String) async throws -> Analysis {
        let client = await instagramClient()
        do {
            let gallery = try await client.post(shortcode: shortcode, url: link.url)
            return .gallery(gallery)
        } catch {
            if error.isCancellation { throw error }
            if let analysis = try? await analyzeVideo(link, forceCookies: settings.cookieBrowser != nil) {
                return analysis
            }
            if settings.cookieBrowser == nil {
                throw DownlyError.needsLogin(.instagram, "Instagram didn’t share this post without signing in.")
            }
            throw error
        }
    }

    func analyzeTikTokPhoto(_ link: ParsedLink, id: String) async throws -> Analysis {
        do {
            return .gallery(try await TikTokClient().photoPost(url: link.url, id: id))
        } catch {
            if error.isCancellation { throw error }
            var components = URLComponents(url: link.url, resolvingAgainstBaseURL: false)
            components?.path = link.url.path.replacingOccurrences(of: "/photo/", with: "/video/")
            if let url = components?.url, let analysis = try? await analyzeVideo(ParsedLink(url: url, platform: .tiktok, kind: .tiktokVideo(id: id))) {
                return analysis
            }
            throw error
        }
    }

    func shouldUseCookies(for link: ParsedLink) -> Bool {
        guard settings.cookieBrowser != nil else { return false }
        if settings.alwaysUseCookies { return true }
        return link.platform == .instagram
    }

    public func analyzeVideo(_ link: ParsedLink, forceCookies: Bool = false) async throws -> Analysis {
        let useCookies = forceCookies || shouldUseCookies(for: link)
        do {
            let json = try await ytdlp.extractInfo(link.url.absoluteString, playlist: false, useCookies: useCookies)
            return interpret(json, link: link, usedCookies: useCookies)
        } catch let error as DownlyError where error.needsAccount && !useCookies && settings.cookieBrowser != nil {
            let json = try await ytdlp.extractInfo(link.url.absoluteString, playlist: false, useCookies: true)
            return interpret(json, link: link, usedCookies: true)
        }
    }

    public func analyzeAny(_ link: ParsedLink) async throws -> Analysis {
        let useCookies = shouldUseCookies(for: link)
        do {
            let json = try await ytdlp.extractInfo(link.url.absoluteString, playlist: true, useCookies: useCookies)
            return interpret(json, link: link, usedCookies: useCookies)
        } catch let error as DownlyError where error.needsAccount && !useCookies && settings.cookieBrowser != nil {
            let json = try await ytdlp.extractInfo(link.url.absoluteString, playlist: true, useCookies: true)
            return interpret(json, link: link, usedCookies: true)
        }
    }

    public func analyzePlaylist(url: String, platform: Platform) async throws -> Analysis {
        guard let parsed = URL(string: url) else { throw DownlyError.unsupportedLink }
        let link = ParsedLink(url: parsed, platform: platform, kind: .youtubePlaylist(id: ""))
        return try await analyzeAny(link)
    }

    func interpret(_ json: J, link: ParsedLink, usedCookies: Bool) -> Analysis {
        let type = json["_type"].string ?? "video"
        if type == "playlist" || (json["entries"].exists && !json["formats"].exists) {
            let entries: [PlaylistEntry] = json["entries"].array.compactMap { entry in
                guard let id = entry["id"].nonEmptyString else { return nil }
                let url = entry["webpage_url"].nonEmptyString ?? entry["url"].nonEmptyString ?? id
                let thumbnail = entry["thumbnails"].array.last?["url"].url ?? entry["thumbnail"].url
                return PlaylistEntry(
                    id: id,
                    title: entry["title"].nonEmptyString ?? "Untitled",
                    url: url,
                    duration: entry["duration"].double,
                    thumbnail: thumbnail,
                    author: entry["channel"].nonEmptyString ?? entry["uploader"].nonEmptyString
                )
            }
            let thumbnail = json["thumbnails"].array.last?["url"].url ?? entries.first?.thumbnail
            let summary = MediaSummary(
                title: json["title"].nonEmptyString ?? "Playlist",
                author: json["channel"].nonEmptyString ?? json["uploader"].nonEmptyString,
                thumbnail: thumbnail,
                duration: entries.compactMap(\.duration).reduce(0, +),
                platform: link.platform,
                webpageURL: link.url
            )
            return .playlist(PlaylistAnalysis(summary: summary, entries: entries, usedCookies: usedCookies))
        }
        let formats = json["formats"].array.map(MediaFormat.init(json:))
        var allFormats = formats
        if allFormats.isEmpty, json["url"].nonEmptyString != nil {
            allFormats = [MediaFormat(json: json)]
        }
        let title = json["title"].nonEmptyString ?? json["fulltitle"].nonEmptyString ?? "Untitled"
        let author = json["channel"].nonEmptyString ?? json["uploader"].nonEmptyString ?? json["creator"].nonEmptyString
        let thumbnail = Analyzer.bestThumbnail(json)
        let webpage = json["webpage_url"].url ?? link.url
        let summary = MediaSummary(
            title: Analyzer.cleanTitle(title, platform: link.platform, author: author),
            author: link.platform == .tiktok || link.platform == .instagram ? author.map { $0.hasPrefix("@") ? $0 : "@\($0)" } : author,
            thumbnail: thumbnail,
            duration: json["duration"].double,
            platform: link.platform,
            webpageURL: webpage
        )
        var playlistURL: String?
        if let list = link.playlistID, !list.hasPrefix("RD"), link.platform == .youtube {
            playlistURL = "https://www.youtube.com/playlist?list=\(list)"
        }
        return .video(VideoAnalysis(
            summary: summary,
            id: json["id"].string ?? UUID().uuidString,
            sourceURL: webpage.absoluteString,
            formats: allFormats,
            isLive: json["is_live"].bool ?? false,
            playlistURL: playlistURL,
            usedCookies: usedCookies,
            isMusicSource: link.isMusic
        ))
    }

    static func bestThumbnail(_ json: J) -> URL? {
        if let direct = json["thumbnail"].url {
            return direct
        }
        return json["thumbnails"].array.last { $0["url"].url != nil }?["url"].url
    }

    static func cleanTitle(_ title: String, platform: Platform, author: String?) -> String {
        var value = title
        if platform == .tiktok || platform == .instagram {
            value = value.replacingOccurrences(of: "\n", with: " ")
            if value.count > 140 {
                value = String(value.prefix(137)) + "…"
            }
        }
        return value
    }
}
