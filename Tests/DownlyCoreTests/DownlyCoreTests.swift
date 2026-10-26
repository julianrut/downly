import XCTest
@testable import DownlyCore

final class LinkParserTests: XCTestCase {
    func testYouTubeForms() {
        XCTAssertEqual(LinkParser.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123")?.kind, .youtubeVideo(id: "dQw4w9WgXcQ"))
        XCTAssertEqual(LinkParser.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123")?.playlistID, "PL123")
        XCTAssertEqual(LinkParser.parse("youtu.be/dQw4w9WgXcQ")?.kind, .youtubeVideo(id: "dQw4w9WgXcQ"))
        XCTAssertEqual(LinkParser.parse("https://m.youtube.com/shorts/abcdEFGhijk")?.kind, .youtubeVideo(id: "abcdEFGhijk"))
        XCTAssertEqual(LinkParser.parse("https://music.youtube.com/watch?v=abcdEFGhijk")?.isMusic, true)
        XCTAssertEqual(LinkParser.parse("https://www.youtube.com/playlist?list=PLxyz")?.kind, .youtubePlaylist(id: "PLxyz"))
        XCTAssertEqual(LinkParser.parse("https://www.youtube.com/@mkbhd")?.kind, .youtubeOther)
    }

    func testSpotifyForms() {
        XCTAssertEqual(LinkParser.parse("https://open.spotify.com/track/abc123")?.kind, .spotifyTrack(id: "abc123"))
        XCTAssertEqual(LinkParser.parse("https://open.spotify.com/intl-fr/album/xyz?si=1")?.kind, .spotifyAlbum(id: "xyz"))
        XCTAssertEqual(LinkParser.parse("spotify:playlist:pl1")?.kind, .spotifyPlaylist(id: "pl1"))
        XCTAssertEqual(LinkParser.parse("https://spotify.link/AbCd")?.kind, .spotifyShort)
    }

    func testInstagramForms() {
        XCTAssertEqual(LinkParser.parse("https://www.instagram.com/p/BQ0eAlwhDrw/?img_index=2")?.kind, .instagramPost(shortcode: "BQ0eAlwhDrw"))
        XCTAssertEqual(LinkParser.parse("https://www.instagram.com/reels/Chunk8-jurw/")?.kind, .instagramPost(shortcode: "Chunk8-jurw"))
        XCTAssertEqual(LinkParser.parse("https://www.instagram.com/natgeo/p/BQ0eAlwhDrw/")?.kind, .instagramPost(shortcode: "BQ0eAlwhDrw"))
        XCTAssertEqual(LinkParser.parse("https://www.instagram.com/stories/natgeo/3000000000000000000/")?.kind, .instagramStory(username: "natgeo", storyID: "3000000000000000000"))
        XCTAssertEqual(LinkParser.parse("https://www.instagram.com/stories/highlights/18090946048123978/")?.kind, .instagramHighlight(id: "18090946048123978"))
        XCTAssertEqual(LinkParser.parse("https://instagram.com/natgeo?igsh=abc")?.kind, .instagramProfile(username: "natgeo"))
        XCTAssertNil(LinkParser.parse("https://www.instagram.com/explore/"))
    }

    func testTikTokForms() {
        XCTAssertEqual(LinkParser.parse("https://www.tiktok.com/@scout2015/video/6718335390845095173")?.kind, .tiktokVideo(id: "6718335390845095173"))
        XCTAssertEqual(LinkParser.parse("https://www.tiktok.com/@someone/photo/7300000000000000001")?.kind, .tiktokPhoto(id: "7300000000000000001"))
        XCTAssertEqual(LinkParser.parse("https://vm.tiktok.com/ZMabc/")?.kind, .tiktokShort)
    }

    func testFirstLinkInText() {
        let parsed = LinkParser.firstLink(in: "check this out https://youtu.be/dQw4w9WgXcQ lol")
        XCTAssertEqual(parsed?.kind, .youtubeVideo(id: "dQw4w9WgXcQ"))
        XCTAssertNil(LinkParser.firstLink(in: "nothing to see here"))
    }

    func testShortcode() {
        XCTAssertEqual(InstagramClient.mediaID(fromShortcode: "BQ0eAlwhDrw"), "1455920561485265648")
    }
}

final class FormatPlannerTests: XCTestCase {
    func format(_ id: String, v: String, a: String, w: Int?, h: Int?, fps: Double? = 30, tbr: Double = 1000, ext: String = "mp4", note: String? = nil) -> MediaFormat {
        MediaFormat(id: id, ext: ext, vcodec: v, acodec: a, width: w, height: h, fps: fps, tbr: tbr, note: note)
    }

    func testYouTubeChoicesAlwaysIncludeAudio() {
        let formats = [
            format("137", v: "avc1.640028", a: "none", w: 1920, h: 1080, tbr: 4000, note: "1080p"),
            format("248", v: "vp9", a: "none", w: 1920, h: 1080, tbr: 3000, ext: "webm", note: "1080p"),
            format("313", v: "vp9", a: "none", w: 3840, h: 2160, tbr: 16000, ext: "webm", note: "2160p"),
            format("140", v: "none", a: "mp4a.40.2", w: nil, h: nil, fps: nil, tbr: 129, ext: "m4a"),
            format("251", v: "none", a: "opus", w: nil, h: nil, fps: nil, tbr: 140, ext: "webm"),
        ]
        let choices = FormatPlanner.videoChoices(formats: formats, duration: 100, preferences: VideoPreferences(container: .mp4, appleCompatible: true), preferMuxed: false)
        XCTAssertEqual(choices.map(\.tier), [2160, 1080])
        XCTAssertEqual(choices[1].video.id, "137")
        XCTAssertEqual(choices[1].audio?.id, "140")
        XCTAssertTrue(choices[1].selector.hasPrefix("137+140/"))
        XCTAssertTrue(choices[0].needsTranscode)
        XCTAssertFalse(choices[1].needsTranscode)

        let original = FormatPlanner.videoChoices(formats: formats, duration: 100, preferences: VideoPreferences(container: .mkv, appleCompatible: false), preferMuxed: false)
        XCTAssertEqual(original[1].video.id, "248")
        XCTAssertEqual(original[1].audio?.id, "251")
    }

    func testVerticalTier() {
        let vertical = format("v", v: "h264", a: "aac", w: 1080, h: 1920)
        XCTAssertEqual(FormatPlanner.tier(of: vertical), 1080)
        let letterbox = format("l", v: "h264", a: "aac", w: 1920, h: 800)
        XCTAssertEqual(FormatPlanner.tier(of: letterbox), 1080)
        let odd = format("o", v: "h264", a: "aac", w: 576, h: 1024)
        XCTAssertEqual(FormatPlanner.tier(of: odd), 480)
    }

    func testMuxedPreferredForTikTok() {
        let formats = [
            format("bytevc1_1080p", v: "h265", a: "none", w: 1080, h: 1920, tbr: 2000),
            format("h264_1080p", v: "h264", a: "aac", w: 1080, h: 1920, tbr: 1500),
        ]
        let choices = FormatPlanner.videoChoices(formats: formats, duration: 30, preferences: VideoPreferences(), preferMuxed: true)
        XCTAssertEqual(choices.first?.video.id, "h264_1080p")
        XCTAssertNil(choices.first?.audio)
    }
}

final class ParsingTests: XCTestCase {
    func testYTDLPProgressLine() {
        let event = YTDLP.parse(line: "DLYP|downloading|1048576|10485760|NA|524288.5|17|137|NA|NA")
        guard case .progress(let progress)? = event else { return XCTFail("no progress") }
        XCTAssertEqual(progress.downloaded, 1_048_576)
        XCTAssertEqual(progress.total, 10_485_760)
        XCTAssertEqual(progress.formatID, "137")
        XCTAssertEqual(progress.eta, 17)
        guard case .file(let path)? = YTDLP.parse(line: "DLYF|/tmp/a b.mp4") else { return XCTFail("no file") }
        XCTAssertEqual(path, "/tmp/a b.mp4")
    }

    func testErrorInterpretation() {
        XCTAssertEqual(YTDLP.interpretError("ERROR: [youtube] abc: Sign in to confirm you’re not a bot.", status: 1), .botCheck)
        XCTAssertEqual(YTDLP.interpretError("ERROR: [generic] Unsupported URL: https://x.y", status: 1), .unsupportedLink)
        XCTAssertEqual(YTDLP.interpretError("ERROR: [youtube] abc: Private video. Sign in", status: 1), .unavailable("This video is private."))
    }

    func testSpotifyEmbedParsing() {
        let html = """
        <html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"type":"album","name":"Discovery","uri":"spotify:album:2noRn2Aes5aoNVsU6iWThc","subtitle":"Daft Punk","releaseDate":{"isoString":"2001-03-12T00:00:00Z"},"coverArt":{"sources":[{"url":"https://i.scdn.co/image/small","width":64},{"url":"https://i.scdn.co/image/big","width":640}]},"trackList":[{"uri":"spotify:track:0DiWol3AO6WpXZgp0goxAV","title":"One More Time","subtitle":"Daft Punk","duration":320357,"isExplicit":false},{"uri":"spotify:track:2VEZx7NWsZ1D0eJ4uv5Fym","title":"Aerodynamic","subtitle":"Daft Punk, Someone Else","duration":212546}]}}}}}}</script></body></html>
        """
        guard let entity = SpotifyClient.parseEmbed(html) else { return XCTFail("no entity") }
        XCTAssertEqual(entity["name"].string, "Discovery")
        XCTAssertEqual(SpotifyClient.bestImage(entity)?.absoluteString, "https://i.scdn.co/image/big")
        XCTAssertEqual(entity["trackList"].array.count, 2)
        XCTAssertEqual(SpotifyClient.splitArtists("Daft Punk, Someone Else & Third"), ["Daft Punk", "Someone Else", "Third"])
    }

    func testTrackMatcher() {
        let track = SpotifyTrack(id: "1", title: "Get Lucky (feat. Pharrell Williams & Nile Rodgers)", artists: ["Daft Punk", "Pharrell Williams", "Nile Rodgers"], durationMs: 369_000)
        let good = MusicCandidate(videoID: "a", title: "Get Lucky (feat. Pharrell Williams & Nile Rodgers)", artists: ["Daft Punk"], album: "Random Access Memories", duration: 369, isSong: true, source: "ytmusic")
        let live = MusicCandidate(videoID: "b", title: "Get Lucky (Live)", artists: ["Daft Punk"], album: nil, duration: 400, isSong: true, source: "ytmusic")
        let cover = MusicCandidate(videoID: "c", title: "Get Lucky - Piano Cover", artists: ["Some Pianist"], album: nil, duration: 250, isSong: false, source: "ytmusic")
        let best = TrackMatcher.best(for: track, among: [cover, live, good])
        XCTAssertEqual(best?.0.videoID, "a")
        XCTAssertGreaterThan(best?.1 ?? 0, 0.8)
    }

    func testYouTubeMusicDuration() {
        XCTAssertEqual(YouTubeMusicSearch.parseDuration("3:45"), 225)
        XCTAssertEqual(YouTubeMusicSearch.parseDuration("1:02:03"), 3723)
        XCTAssertNil(YouTubeMusicSearch.parseDuration("1.2M plays"))
    }

    func testNetscapeCookies() {
        let text = "# Netscape HTTP Cookie File\n.instagram.com\tTRUE\t/\tTRUE\t2000000000\tsessionid\tabc\n#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t2000000000\tcsrftoken\txyz\n"
        let cookies = BrowserCookies.parseNetscape(text)
        XCTAssertEqual(cookies.count, 2)
        let snapshot = BrowserCookieSnapshot(browser: .chrome, cookies: cookies, date: Date())
        XCTAssertEqual(snapshot.value("csrftoken", domain: "instagram.com"), "xyz")
        XCTAssertTrue(snapshot.headerValue(forDomain: "instagram.com").contains("sessionid=abc"))
    }

    func testSanitize() {
        XCTAssertEqual(FileNamer.sanitize("a/b: c\nd"), "a-b - c d")
        XCTAssertEqual(FileNamer.sanitize("   "), "Download")
    }
}
