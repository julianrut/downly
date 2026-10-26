import Foundation

public struct TikTokClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(userAgent: UserAgent.chrome)) {
        self.http = http
    }

    public func resolve(_ url: URL) async -> URL {
        await http.finalURL(for: url)
    }

    public func photoPost(url: URL, id: String) async throws -> Gallery {
        let result = try await http.get(url, headers: [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Dest": "document",
        ])
        guard result.isSuccess else { throw DownlyError.http(result.status) }
        guard let item = TikTokClient.itemStruct(fromHTML: result.text) else {
            throw DownlyError.unavailable("TikTok didn’t share this post. Try again in a moment.")
        }
        return try TikTokClient.gallery(from: item, id: id, url: url)
    }

    public static func itemStruct(fromHTML html: String) -> J? {
        for content in TextScan.scriptContents(in: html, matchingAttributes: "id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"']") {
            let json = J(string: content)
            let item = json["__DEFAULT_SCOPE__"]["webapp.video-detail"]["itemInfo"]["itemStruct"]
            if item.exists { return item }
            if let found = json.firstValue(forKey: "itemStruct"), found.exists { return found }
        }
        for content in TextScan.scriptContents(in: html, matchingAttributes: "id=[\"']SIGI_STATE[\"']") {
            let json = J(string: content)
            if let module = json["ItemModule"].dictionary.values.first { return module }
        }
        return nil
    }

    static func gallery(from item: J, id: String, url: URL) throws -> Gallery {
        let author = item["author"]["uniqueId"].nonEmptyString ?? item["author"].nonEmptyString ?? "tiktok"
        let description = item["desc"].nonEmptyString
        let base = FileNamer.sanitize("\(author) \(id)", maxLength: 80)
        var items: [GalleryItem] = []
        let headers = ["Referer": "https://www.tiktok.com/"]
        for (index, image) in item["imagePost"]["images"].array.enumerated() {
            let urls = image["imageURL"]["urlList"].array.compactMap(\.url)
            let preferred = urls.first { $0.absoluteString.contains(".jpeg") || $0.absoluteString.contains(".jpg") } ?? urls.first
            guard let preferred else { continue }
            items.append(GalleryItem(id: "\(id)-\(index)", kind: .photo, url: preferred, thumbnail: preferred, width: image["imageWidth"].int, height: image["imageHeight"].int, headers: headers, suggestedName: "\(base) \(index + 1)"))
        }
        var sections: [GallerySection] = []
        if !items.isEmpty {
            sections.append(GallerySection(id: "photos", title: "\(items.count) photos", items: items))
        }
        if let music = item["music"]["playUrl"].url {
            let title = item["music"]["title"].nonEmptyString ?? "Sound"
            let audio = GalleryItem(id: "\(id)-audio", kind: .audio, url: music, thumbnail: item["music"]["coverLarge"].url, headers: headers, suggestedName: FileNamer.sanitize("\(author) - \(title)"))
            sections.append(GallerySection(id: "sound", title: "Sound", items: [audio]))
        }
        guard !sections.isEmpty else { throw DownlyError.nothingToDownload }
        let summary = MediaSummary(
            title: InstagramClient.titleFrom(caption: description, fallback: "Photos by @\(author)"),
            author: "@\(author)",
            thumbnail: items.first?.thumbnail ?? item["video"]["cover"].url,
            platform: .tiktok,
            webpageURL: url
        )
        return Gallery(summary: summary, sections: sections, folderName: base, isProfile: false)
    }
}

public struct QuickPreview: Sendable {
    let http = HTTPClient(userAgent: UserAgent.safari, timeout: 8, storesCookies: false)

    public init() {}

    public func summary(for link: ParsedLink) async -> MediaSummary? {
        switch link.kind {
        case .youtubeVideo(let id):
            guard let json = await oembed("https://www.youtube.com/oembed?format=json&url=\(encode(link.url.absoluteString))") else {
                return MediaSummary(title: "YouTube video", thumbnail: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"), platform: .youtube, webpageURL: link.url)
            }
            return MediaSummary(
                title: json["title"].nonEmptyString ?? "YouTube video",
                author: json["author_name"].nonEmptyString,
                thumbnail: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
                platform: .youtube,
                webpageURL: link.url
            )
        case .youtubePlaylist:
            guard let json = await oembed("https://www.youtube.com/oembed?format=json&url=\(encode(link.url.absoluteString))") else { return nil }
            return MediaSummary(title: json["title"].nonEmptyString ?? "Playlist", author: json["author_name"].nonEmptyString, thumbnail: json["thumbnail_url"].url, platform: .youtube, webpageURL: link.url)
        case .tiktokVideo, .tiktokPhoto:
            guard let json = await oembed("https://www.tiktok.com/oembed?url=\(encode(link.url.absoluteString))") else { return nil }
            return MediaSummary(title: json["title"].nonEmptyString ?? "TikTok", author: json["author_name"].nonEmptyString.map { "@\($0)" }, thumbnail: json["thumbnail_url"].url, platform: .tiktok, webpageURL: link.url)
        case .spotifyTrack, .spotifyAlbum, .spotifyPlaylist, .spotifyArtist:
            guard let json = await oembed("https://open.spotify.com/oembed?url=\(encode(link.url.absoluteString))") else { return nil }
            return MediaSummary(title: json["title"].nonEmptyString ?? "Spotify", thumbnail: json["thumbnail_url"].url, platform: .spotify, webpageURL: link.url)
        default:
            return nil
        }
    }

    func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    func oembed(_ string: String) async -> J? {
        guard let url = URL(string: string), let result = try? await http.get(url), result.isSuccess else { return nil }
        let json = result.json
        return json.exists ? json : nil
    }
}
