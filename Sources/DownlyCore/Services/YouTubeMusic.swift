import Foundation

public struct MusicCandidate: Sendable, Hashable {
    public var videoID: String
    public var title: String
    public var artists: [String]
    public var album: String?
    public var duration: Double?
    public var isSong: Bool
    public var source: String

    public var url: String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }
}

public struct YouTubeMusicSearch: Sendable {
    let http: HTTPClient
    static let songsParams = "EgWKAQIIAWoKEAoQAxAEEAkQBQ=="
    static let videosParams = "EgWKAQIQAWoKEAoQAxAEEAkQBQ=="

    public init(http: HTTPClient = HTTPClient(userAgent: UserAgent.chrome)) {
        self.http = http
    }

    static var clientVersion: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        let date = Date().addingTimeInterval(-3 * 24 * 3600)
        return "1.\(formatter.string(from: date)).01.00"
    }

    public func search(_ query: String, songsOnly: Bool = true) async throws -> [MusicCandidate] {
        let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false")!
        let version = YouTubeMusicSearch.clientVersion
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": version,
                    "hl": "en",
                    "gl": "US",
                ],
            ],
            "query": query,
            "params": songsOnly ? YouTubeMusicSearch.songsParams : YouTubeMusicSearch.videosParams,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let result = try await http.post(url, headers: [
            "Content-Type": "application/json",
            "Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/",
            "X-Youtube-Client-Name": "67",
            "X-Youtube-Client-Version": version,
        ], body: data)
        guard result.isSuccess else {
            throw DownlyError.http(result.status)
        }
        return YouTubeMusicSearch.parse(result.json, defaultIsSong: songsOnly)
    }

    public static func parse(_ json: J, defaultIsSong: Bool) -> [MusicCandidate] {
        var output: [MusicCandidate] = []
        var seen = Set<String>()
        for renderer in json.findAll(key: "musicResponsiveListItemRenderer") {
            guard let candidate = candidate(from: renderer, defaultIsSong: defaultIsSong), !seen.contains(candidate.videoID) else { continue }
            seen.insert(candidate.videoID)
            output.append(candidate)
        }
        return output
    }

    static func candidate(from renderer: J, defaultIsSong: Bool) -> MusicCandidate? {
        let columns = renderer["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"] }
        guard let titleRuns = columns.first, let title = titleRuns[0]["text"].nonEmptyString else { return nil }
        let videoID = renderer["playlistItemData"]["videoId"].nonEmptyString
            ?? titleRuns[0]["navigationEndpoint"]["watchEndpoint"]["videoId"].nonEmptyString
            ?? renderer["overlay"]["musicItemThumbnailOverlayRenderer"]["content"]["musicPlayButtonRenderer"]["playNavigationEndpoint"]["watchEndpoint"]["videoId"].nonEmptyString
        guard let videoID else { return nil }

        let videoType = titleRuns[0]["navigationEndpoint"]["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
            ?? renderer["overlay"]["musicItemThumbnailOverlayRenderer"]["content"]["musicPlayButtonRenderer"]["playNavigationEndpoint"]["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string

        var artists: [String] = []
        var album: String?
        var duration: Double?
        var plainGroups: [String] = []
        var currentGroup = ""
        var allRuns: [J] = []
        for column in columns.dropFirst() {
            allRuns += column.array
        }
        for fixed in renderer["fixedColumns"].array {
            allRuns += fixed["musicResponsiveListItemFixedColumnRenderer"]["text"]["runs"].array
        }
        for run in allRuns {
            let text = run["text"].string ?? ""
            if text.trimmingCharacters(in: .whitespaces) == "•" {
                if !currentGroup.isEmpty { plainGroups.append(currentGroup) }
                currentGroup = ""
                continue
            }
            let pageType = run["navigationEndpoint"]["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].string ?? ""
            let browseID = run["navigationEndpoint"]["browseEndpoint"]["browseId"].string ?? ""
            if pageType == "MUSIC_PAGE_TYPE_ARTIST" || pageType == "MUSIC_PAGE_TYPE_USER_CHANNEL" || browseID.hasPrefix("UC") {
                artists.append(text)
            } else if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseID.hasPrefix("MPRE") {
                album = text
            } else if let seconds = parseDuration(text) {
                duration = seconds
            }
            currentGroup += text
        }
        if !currentGroup.isEmpty { plainGroups.append(currentGroup) }

        let typeWords: Set<String> = ["song", "video", "episode", "single", "ep", "album"]
        let groups = plainGroups.filter { !typeWords.contains($0.lowercased()) }
        if artists.isEmpty, let first = groups.first, parseDuration(first) == nil {
            artists = SpotifyClient.splitArtists(first)
        }
        if duration == nil {
            duration = groups.compactMap(parseDuration).last
        }
        let isSong: Bool
        if let videoType {
            isSong = videoType == "MUSIC_VIDEO_TYPE_ATV"
        } else {
            isSong = defaultIsSong || plainGroups.first?.lowercased() == "song"
        }
        return MusicCandidate(videoID: videoID, title: title, artists: artists, album: album, duration: duration, isSong: isSong, source: "ytmusic")
    }

    static func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2, parts.count <= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        var total = 0.0
        for part in parts {
            total = total * 60 + (Double(part) ?? 0)
        }
        return total
    }
}

public enum TrackMatcher {
    static let suspiciousWords = [
        "live", "remix", "cover", "karaoke", "instrumental", "acoustic", "sped up", "speed up", "slowed", "reverb", "8d",
        "nightcore", "mashup", "reaction", "tutorial", "lesson", "piano version", "bass boosted", "loop", "1 hour", "extended",
    ]

    public static func normalize(_ text: String) -> String {
        var value = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
        value = value.replacingOccurrences(of: "&", with: " and ")
        value = value.replacingOccurrences(of: #"\((feat|ft|with)\.?[^)]*\)"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[(feat|ft|with)\.?[^\]]*\]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(feat|ft)\.? .*$"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[\(\[](official|lyric|lyrics|audio|video|visualizer|music video|hd|hq|4k|mv|m/v)[^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(official music video|official video|official audio|official lyric video|lyric video|lyrics video|visualizer)\b"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^\p{L}\p{N} ]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(normalize(text).split(separator: " ").map(String.init))
    }

    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let lhs = Array(a)
        let rhs = Array(b)
        if lhs.isEmpty && rhs.isEmpty { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        let distance = previous[rhs.count]
        return 1 - Double(distance) / Double(max(lhs.count, rhs.count))
    }

    public static func titleScore(_ spotifyTitle: String, _ candidateTitle: String, artists: [String]) -> Double {
        let a = normalize(spotifyTitle)
        var b = normalize(candidateTitle)
        for artist in artists {
            let normalizedArtist = normalize(artist)
            if !normalizedArtist.isEmpty, b.hasPrefix(normalizedArtist + " ") {
                b = String(b.dropFirst(normalizedArtist.count + 1))
            }
        }
        let ta = Set(a.split(separator: " ").map(String.init))
        let tb = Set(b.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let shared = Double(ta.intersection(tb).count)
        let containment = shared / Double(ta.count)
        let jaccard = shared / Double(ta.union(tb).count)
        let ratio = levenshteinRatio(a, b)
        return max(ratio, containment * 0.92, jaccard)
    }

    public static func artistScore(_ spotifyArtists: [String], candidate: MusicCandidate) -> Double {
        guard !spotifyArtists.isEmpty else { return 0.5 }
        let haystack = normalize(candidate.artists.joined(separator: " ") + " " + candidate.title)
        let candidateArtistTokens = tokens(candidate.artists.joined(separator: " "))
        var matched = 0.0
        for (index, artist) in spotifyArtists.enumerated() {
            let name = normalize(artist)
            guard !name.isEmpty else { continue }
            let weight = index == 0 ? 1.0 : 0.5
            if haystack.contains(name) {
                matched += weight
            } else {
                let artistTokens = Set(name.split(separator: " ").map(String.init))
                let overlap = Double(artistTokens.intersection(candidateArtistTokens).count) / Double(max(artistTokens.count, 1))
                matched += weight * (overlap >= 0.5 ? overlap * 0.8 : 0)
            }
        }
        let possible = 1.0 + Double(max(spotifyArtists.count - 1, 0)) * 0.5
        let base = matched / possible
        let main = normalize(spotifyArtists[0])
        if haystack.contains(main) {
            return max(base, 0.75)
        }
        return base
    }

    public static func durationScore(_ expected: Double?, _ actual: Double?) -> Double {
        guard let expected, let actual else { return 0.5 }
        let diff = abs(expected - actual)
        if diff <= 2 { return 1 }
        if diff >= 30 { return 0 }
        return 1 - (diff - 2) / 28
    }

    public static func penalty(spotifyTitle: String, candidateTitle: String) -> Double {
        let source = normalize(spotifyTitle)
        let target = normalize(candidateTitle)
        var total = 0.0
        for word in suspiciousWords where target.contains(word) && !source.contains(word) {
            total += 0.22
        }
        return min(total, 0.6)
    }

    public static func score(_ track: SpotifyTrack, _ candidate: MusicCandidate) -> Double {
        let title = titleScore(track.title, candidate.title, artists: candidate.artists)
        let artist = artistScore(track.artists, candidate: candidate)
        let duration = durationScore(track.duration, candidate.duration)
        var total = title * 0.45 + artist * 0.3 + duration * 0.25
        total -= penalty(spotifyTitle: track.title, candidateTitle: candidate.title)
        if candidate.isSong { total += 0.05 }
        if let expected = track.duration, let actual = candidate.duration, abs(expected - actual) > 60 {
            total -= 0.3
        }
        return total
    }

    public static func best(for track: SpotifyTrack, among candidates: [MusicCandidate]) -> (MusicCandidate, Double)? {
        candidates
            .map { ($0, score(track, $0)) }
            .max { $0.1 < $1.1 }
    }
}

public struct TrackResolver: Sendable {
    let search: YouTubeMusicSearch
    let ytdlp: YTDLP?

    public init(search: YouTubeMusicSearch = YouTubeMusicSearch(), ytdlp: YTDLP?) {
        self.search = search
        self.ytdlp = ytdlp
    }

    public func resolve(_ track: SpotifyTrack) async throws -> (MusicCandidate, Double) {
        let primaryArtist = track.artists.first ?? ""
        var best: (MusicCandidate, Double)?
        func consider(_ candidates: [MusicCandidate]) {
            if let found = TrackMatcher.best(for: track, among: candidates), found.1 > (best?.1 ?? -1) {
                best = found
            }
        }
        let queries = [
            "\(track.artists.joined(separator: " ")) \(track.title)",
            "\(primaryArtist) - \(track.title)",
        ]
        for query in queries {
            if let candidates = try? await search.search(query, songsOnly: true) {
                consider(Array(candidates.prefix(8)))
            }
            if let best, best.1 >= 0.82 { return best }
        }
        if let candidates = try? await search.search("\(primaryArtist) \(track.title)", songsOnly: false) {
            consider(Array(candidates.prefix(6)))
        }
        if let best, best.1 >= 0.62 { return best }
        if let ytdlp, let fallback = try? await youtubeSearch("\(primaryArtist) - \(track.title) audio", ytdlp: ytdlp) {
            consider(fallback)
        }
        if let best, best.1 >= 0.5 { return best }
        if let best {
            throw DownlyError.noMatch("Couldn’t find a confident match for “\(track.title)” (closest: “\(best.0.title)”).")
        }
        throw DownlyError.noMatch("Couldn’t find “\(track.title)” on YouTube Music.")
    }

    func youtubeSearch(_ query: String, ytdlp: YTDLP) async throws -> [MusicCandidate] {
        let json = try await ytdlp.extractInfo("ytsearch8:\(query)", playlist: true, useCookies: false)
        return json["entries"].array.compactMap { entry in
            guard let id = entry["id"].nonEmptyString, let title = entry["title"].nonEmptyString else { return nil }
            let channel = entry["channel"].nonEmptyString ?? entry["uploader"].nonEmptyString ?? ""
            let artist = channel.replacingOccurrences(of: " - Topic", with: "").replacingOccurrences(of: "VEVO", with: "")
            return MusicCandidate(videoID: id, title: title, artists: artist.isEmpty ? [] : [artist], album: nil, duration: entry["duration"].double, isSong: channel.hasSuffix(" - Topic"), source: "youtube")
        }
    }
}
