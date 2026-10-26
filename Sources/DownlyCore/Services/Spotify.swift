import Foundation

public struct SpotifyClient: Sendable {
    let http: HTTPClient

    public static let sharedHTTP = HTTPClient(userAgent: UserAgent.safari)

    public init(http: HTTPClient = SpotifyClient.sharedHTTP) {
        self.http = http
    }

    public func resolveShortLink(_ url: URL) async -> URL {
        let final = await http.finalURL(for: url)
        if final.host?.contains("open.spotify.com") == true {
            return final
        }
        if let result = try? await http.get(url) {
            if let match = TextScan.first("(https://open\\.spotify\\.com/(?:track|album|playlist|artist)/[A-Za-z0-9]+)", in: result.text) {
                return URL(string: match) ?? final
            }
        }
        return final
    }

    public func fetch(type: String, id: String) async throws -> MusicCollection {
        let entity = try await embedEntity(type: type, id: id)
        let webURL = URL(string: "https://open.spotify.com/\(type)/\(id)")!
        let name = entity["name"].nonEmptyString ?? entity["title"].nonEmptyString ?? "Spotify"
        let cover = SpotifyClient.bestImage(entity)
        let entityType = entity["type"].string ?? type

        if entityType == "track" || type == "track" {
            var track = SpotifyClient.track(from: entity, fallbackID: id, cover: cover)
            if track.album == nil {
                if let details = try? await trackPageDetails(id: id) {
                    track.album = details.album ?? track.album
                    if track.releaseDate == nil { track.releaseDate = details.year }
                }
            }
            let summary = MediaSummary(title: track.title, author: track.artistLine, thumbnail: track.cover, duration: track.duration, platform: .spotify, webpageURL: webURL)
            return MusicCollection(summary: summary, kind: .track, tracks: [track], totalTracks: 1)
        }

        let kind = MusicCollectionKind(rawValue: entityType) ?? MusicCollectionKind(rawValue: type) ?? .playlist
        let artistNames = entity["artists"].array.compactMap { $0["name"].nonEmptyString }.joined(separator: ", ")
        let owner: String = entity["subtitle"].nonEmptyString
            ?? entity["authors"][0]["name"].nonEmptyString
            ?? entity["ownerV2"]["data"]["name"].nonEmptyString
            ?? artistNames
        let release = entity["releaseDate"]["isoString"].nonEmptyString ?? entity["releaseDate"].nonEmptyString
        var tracks: [SpotifyTrack] = []
        for (index, item) in entity["trackList"].array.enumerated() {
            guard let uri = item["uri"].string, uri.contains(":track:") else { continue }
            let trackID = String(uri.split(separator: ":").last ?? "")
            let title = item["title"].nonEmptyString ?? item["name"].nonEmptyString ?? "Track \(index + 1)"
            let artistNames = item["artists"].array.compactMap { $0["name"].nonEmptyString }
            let subtitle = item["subtitle"].nonEmptyString ?? ""
            let artists = artistNames.isEmpty ? SpotifyClient.splitArtists(subtitle) : artistNames
            tracks.append(SpotifyTrack(
                id: trackID,
                title: title,
                artists: artists,
                album: kind == .album ? name : nil,
                durationMs: item["duration"].int,
                cover: kind == .album ? cover : nil,
                releaseDate: kind == .album ? release : nil,
                trackNumber: kind == .album ? index + 1 : nil,
                explicit: item["isExplicit"].bool ?? false
            ))
        }
        if tracks.isEmpty {
            throw DownlyError.nothingToDownload
        }
        let summary = MediaSummary(
            title: name,
            author: owner.isEmpty ? nil : owner,
            thumbnail: cover,
            duration: tracks.compactMap(\.duration).reduce(0, +),
            platform: .spotify,
            webpageURL: webURL
        )
        return MusicCollection(summary: summary, kind: kind, tracks: tracks, totalTracks: entity["totalCount"].int ?? tracks.count)
    }

    public func enrich(_ track: SpotifyTrack) async -> SpotifyTrack {
        var output = track
        if output.cover == nil || output.releaseDate == nil {
            if let entity = try? await embedEntity(type: "track", id: track.id) {
                let full = SpotifyClient.track(from: entity, fallbackID: track.id, cover: SpotifyClient.bestImage(entity))
                output.cover = output.cover ?? full.cover
                output.releaseDate = output.releaseDate ?? full.releaseDate
                if output.artists.count < full.artists.count {
                    output.artists = full.artists
                }
                output.durationMs = output.durationMs ?? full.durationMs
            }
        }
        if output.album == nil, let details = try? await trackPageDetails(id: track.id) {
            output.album = details.album
            output.releaseDate = output.releaseDate ?? details.year
        }
        return output
    }

    func embedEntity(type: String, id: String) async throws -> J {
        let url = URL(string: "https://open.spotify.com/embed/\(type)/\(id)")!
        var lastError: Error = DownlyError.unavailable("Couldn’t read this from Spotify.")
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(400_000_000 * attempt))
            }
            let result: HTTPResult
            do {
                result = try await http.get(url, headers: ["Accept": "text/html,application/xhtml+xml"])
            } catch {
                if error.isCancellation { throw error }
                lastError = error
                continue
            }
            if result.status == 404 {
                throw DownlyError.unavailable("Spotify says this doesn’t exist.")
            }
            if result.isSuccess, let entity = SpotifyClient.parseEmbed(result.text) {
                return entity
            }
            lastError = result.isSuccess
                ? DownlyError.unavailable("Spotify changed its page format. Please update Downly.")
                : DownlyError.http(result.status)
        }
        throw lastError
    }

    public static func parseEmbed(_ html: String) -> J? {
        for content in TextScan.scriptContents(in: html, matchingAttributes: "id=[\"']__NEXT_DATA__[\"']") {
            let json = J(string: content)
            let entity = json[["props", "pageProps", "state", "data", "entity"]]
            if entity.exists { return entity }
            if let found = findEntity(json) { return found }
        }
        for attribute in ["resource", "initial-state", "initialState"] {
            for content in TextScan.scriptContents(in: html, matchingAttributes: "id=[\"']\(attribute)[\"']") {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                var json = J(string: trimmed)
                if !json.exists, let data = Data(base64Encoded: trimmed) {
                    json = J(data: data)
                }
                if json["data"]["entity"].exists { return json["data"]["entity"] }
                if let found = findEntity(json) { return found }
            }
        }
        for content in TextScan.scriptContents(in: html, matchingAttributes: "type=[\"']application/json[\"']") {
            if let found = findEntity(J(string: content)) { return found }
        }
        return nil
    }

    static func findEntity(_ json: J) -> J? {
        json.findObjects(limit: 1) { object in
            guard let uri = object["uri"] as? String, uri.hasPrefix("spotify:") else { return false }
            return object["name"] != nil || object["title"] != nil
        }.first
    }

    static func bestImage(_ entity: J) -> URL? {
        var candidates: [(URL, Int)] = []
        for list in [entity["coverArt"]["sources"], entity["images"], entity["visualIdentity"]["image"], entity["album"]["images"]] {
            for image in list.array {
                guard let url = image["url"].url else { continue }
                let size = image["width"].int ?? image["maxWidth"].int ?? image["maxHeight"].int ?? 0
                candidates.append((url, size))
            }
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    static func track(from entity: J, fallbackID: String, cover: URL?) -> SpotifyTrack {
        let id = entity["uri"].string.map { String($0.split(separator: ":").last ?? "") } ?? entity["id"].string ?? fallbackID
        let title = entity["name"].nonEmptyString ?? entity["title"].nonEmptyString ?? "Unknown"
        var artists = entity["artists"].array.compactMap { $0["name"].nonEmptyString }
        if artists.isEmpty, let subtitle = entity["subtitle"].nonEmptyString {
            artists = splitArtists(subtitle)
        }
        let duration = entity["duration"].int ?? entity["duration"]["totalMilliseconds"].int ?? entity["duration_ms"].int
        let release = entity["releaseDate"]["isoString"].nonEmptyString ?? entity["releaseDate"].nonEmptyString
        let album = entity["album"]["name"].nonEmptyString ?? entity["albumOfTrack"]["name"].nonEmptyString
        return SpotifyTrack(
            id: id.isEmpty ? fallbackID : id,
            title: title,
            artists: artists,
            album: album,
            durationMs: duration,
            cover: cover,
            releaseDate: release,
            explicit: entity["isExplicit"].bool ?? false
        )
    }

    static func splitArtists(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: " & ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func trackPageDetails(id: String) async throws -> (album: String?, year: String?) {
        let url = URL(string: "https://open.spotify.com/track/\(id)")!
        let result = try await http.getOK(url, headers: ["Accept": "text/html"])
        let html = result.text
        if let entity = SpotifyClient.parseEmbed(html) {
            let album = entity["albumOfTrack"]["name"].nonEmptyString ?? entity["album"]["name"].nonEmptyString
            if album != nil {
                return (album, entity["albumOfTrack"]["date"]["year"].string)
            }
        }
        if let description = TextScan.metaContent("og:description", in: html) {
            let parts = description.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
            if let songIndex = parts.firstIndex(where: { $0.lowercased() == "song" }), songIndex >= 2 {
                let year = parts.last.flatMap { $0.count == 4 && Int($0) != nil ? $0 : nil }
                return (parts[songIndex - 1], year)
            }
        }
        return (nil, nil)
    }
}
