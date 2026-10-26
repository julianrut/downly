import Foundation

public struct InstagramClient: Sendable {
    static let appID = "936619743392459"
    static let shortcodeAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    let http: HTTPClient
    let session: BrowserCookieSnapshot?

    public init(session: BrowserCookieSnapshot?) {
        self.http = HTTPClient(userAgent: UserAgent.safari, timeout: 25, storesCookies: true)
        self.session = session
    }

    public var isLoggedIn: Bool {
        session?.value("sessionid", domain: "instagram.com")?.isEmpty == false
    }

    public static func mediaID(fromShortcode shortcode: String) -> String? {
        var code = shortcode
        if code.count > 28 {
            code = String(code.prefix(code.count - 28))
        }
        var value: UInt64 = 0
        for character in code {
            guard let index = shortcodeAlphabet.firstIndex(of: character) else { return nil }
            let (multiplied, overflow1) = value.multipliedReportingOverflow(by: 64)
            let (added, overflow2) = multiplied.addingReportingOverflow(UInt64(index))
            if overflow1 || overflow2 { return nil }
            value = added
        }
        return String(value)
    }

    var apiHeaders: [String: String] {
        var headers: [String: String] = [
            "X-IG-App-ID": InstagramClient.appID,
            "X-ASBD-ID": "359341",
            "X-IG-WWW-Claim": "0",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": "https://www.instagram.com",
            "Referer": "https://www.instagram.com/",
            "Accept": "*/*",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
        ]
        if let session {
            let cookie = session.headerValue(forDomain: "instagram.com")
            if !cookie.isEmpty {
                headers["Cookie"] = cookie
            }
            if let csrf = session.value("csrftoken", domain: "instagram.com") {
                headers["X-CSRFToken"] = csrf
            }
        }
        return headers
    }

    static let mediaHeaders = ["Referer": "https://www.instagram.com/", "Accept": "image/avif,image/webp,image/jpeg,image/*,video/*,*/*;q=0.8"]

    func api(_ path: String) async throws -> J {
        guard let url = URL(string: "https://www.instagram.com/api/v1/\(path)") else { throw DownlyError.unsupportedLink }
        let result = try await http.get(url, headers: apiHeaders)
        if result.status == 401 || result.status == 403 || result.finalURL.path.contains("/accounts/login") {
            throw DownlyError.needsLogin(.instagram, "Instagram wants you to be signed in to see this.")
        }
        if result.status == 429 {
            throw DownlyError.needsLogin(.instagram, "Instagram is limiting requests right now. Signing in usually fixes this.")
        }
        if result.status == 404 {
            throw DownlyError.unavailable("This Instagram content doesn’t exist or was removed.")
        }
        guard result.isSuccess else { throw DownlyError.http(result.status) }
        let json = result.json
        if json["require_login"].bool == true || json["message"].string == "login_required" {
            throw DownlyError.needsLogin(.instagram, "Instagram wants you to be signed in to see this.")
        }
        return json
    }

    public func post(shortcode: String, url: URL) async throws -> Gallery {
        guard let mediaID = InstagramClient.mediaID(fromShortcode: shortcode) else { throw DownlyError.unsupportedLink }
        var product: J?
        var lastError: Error?
        if isLoggedIn {
            do {
                let json = try await api("media/\(mediaID)/info/")
                product = json["items"][0].exists ? json["items"][0] : nil
            } catch {
                if error.isCancellation { throw error }
                lastError = error
            }
        }
        if product == nil {
            do {
                product = try await anonymousProduct(shortcode: shortcode, mediaID: mediaID)
            } catch {
                if error.isCancellation { throw error }
                lastError = lastError ?? error
            }
        }
        if let product {
            return try gallery(fromProduct: product, shortcode: shortcode, url: url)
        }
        if let legacy = try? await embedLegacy(shortcode: shortcode, url: url) {
            return legacy
        }
        throw lastError ?? DownlyError.needsLogin(.instagram, "Instagram didn’t share this post without signing in.")
    }

    func anonymousProduct(shortcode: String, mediaID: String) async throws -> J? {
        let pageURL = URL(string: "https://www.instagram.com/p/\(shortcode)/")!
        let page = try await http.get(pageURL, headers: [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Site": "none",
        ])
        let html = page.text
        if let embedded = InstagramClient.findProduct(inHTML: html) {
            return embedded
        }
        let lsd = TextScan.first(#""LSD",\[\],\{"token":"([^"]+)""#, in: html)
            ?? TextScan.first(#""lsd":"([^"]+)""#, in: html)
            ?? TextScan.first(#"name="lsd" value="([^"]+)""#, in: html)
        _ = try? await http.get(URL(string: "https://www.instagram.com/api/v1/web/get_ruling_for_content/?content_type=MEDIA&target_id=\(mediaID)")!, headers: apiHeaders)
        let csrf = http.cookies(for: URL(string: "https://www.instagram.com/")!).first { $0.name == "csrftoken" }?.value
        guard let lsd else { return nil }
        let variables = "{\"media_id\":\"\(mediaID)\"}"
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "lsd", value: lsd),
            URLQueryItem(name: "fb_api_caller_class", value: "RelayModern"),
            URLQueryItem(name: "fb_api_req_friendly_name", value: "PolarisLoggedOutDesktopWWWPostRootContentQuery"),
            URLQueryItem(name: "server_timestamps", value: "true"),
            URLQueryItem(name: "variables", value: variables),
            URLQueryItem(name: "doc_id", value: "27130156389949648"),
        ]
        let body = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        var headers = apiHeaders
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["X-FB-LSD"] = lsd
        headers["X-FB-Friendly-Name"] = "PolarisLoggedOutDesktopWWWPostRootContentQuery"
        headers["Referer"] = pageURL.absoluteString
        if let csrf { headers["X-CSRFToken"] = csrf }
        let response = try await http.post(URL(string: "https://www.instagram.com/api/graphql")!, headers: headers, body: Data(body.utf8))
        let json = response.json
        let media = json["data"]["xig_polaris_media"]["if_not_gated_logged_out"]
        if media.exists { return media }
        return InstagramClient.findProduct(in: json)
    }

    static func findProduct(inHTML html: String) -> J? {
        for content in TextScan.scriptContents(in: html, matchingAttributes: "type=[\"']application/json[\"']") where content.contains("image_versions2") || content.contains("video_versions") {
            if let product = findProduct(in: J(string: content)) {
                return product
            }
        }
        return nil
    }

    static func findProduct(in json: J) -> J? {
        json.findObjects(limit: 1) { object in
            (object["image_versions2"] != nil || object["carousel_media"] != nil) && (object["code"] != nil || object["pk"] != nil)
        }.first
    }

    func gallery(fromProduct product: J, shortcode: String, url: URL) throws -> Gallery {
        let username = product["user"]["username"].nonEmptyString ?? product["owner"]["username"].nonEmptyString
        let caption = product["caption"]["text"].nonEmptyString
        let mediaItems: [J] = product["carousel_media"].array.isEmpty ? [product] : product["carousel_media"].array
        let base = FileNamer.sanitize("\(username ?? "instagram") \(shortcode)", maxLength: 80)
        var items: [GalleryItem] = []
        for (index, media) in mediaItems.enumerated() {
            let suffix = mediaItems.count > 1 ? " \(index + 1)" : ""
            if let item = InstagramClient.item(from: media, id: "\(shortcode)-\(index)", name: base + suffix) {
                items.append(item)
            }
        }
        guard !items.isEmpty else { throw DownlyError.nothingToDownload }
        if items.count == 1, items[0].kind == .video {
            items[0].ytdlpURL = url.absoluteString
        }
        let title = InstagramClient.titleFrom(caption: caption, fallback: username.map { "Post by @\($0)" } ?? "Instagram post")
        let summary = MediaSummary(
            title: title,
            author: username.map { "@\($0)" },
            thumbnail: items.first?.thumbnail ?? items.first?.url,
            duration: product["video_duration"].double,
            platform: .instagram,
            webpageURL: url
        )
        let sectionTitle = items.count == 1 ? (items[0].kind == .video ? "Video" : "Photo") : "\(items.count) items"
        return Gallery(summary: summary, sections: [GallerySection(id: "post", title: sectionTitle, items: items)], folderName: base, isProfile: false)
    }

    static func titleFrom(caption: String?, fallback: String) -> String {
        guard let caption else { return fallback }
        let firstLine = caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? caption
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fallback }
        return trimmed.count > 120 ? String(trimmed.prefix(117)) + "…" : trimmed
    }

    static func item(from media: J, id: String, name: String) -> GalleryItem? {
        let images = media["image_versions2"]["candidates"].array
        let bestImage = images.max { ($0["width"].int ?? 0) * ($0["height"].int ?? 0) < ($1["width"].int ?? 0) * ($1["height"].int ?? 0) }
        let thumbnail = images.min { abs(($0["width"].int ?? 0) - 640) < abs(($1["width"].int ?? 0) - 640) }?["url"].url ?? bestImage?["url"].url
        let videos = media["video_versions"].array
        let takenAt = media["taken_at"].double.map { Date(timeIntervalSince1970: $0) }
        let mediaID = media["pk"].string ?? media["id"].string ?? id
        if !videos.isEmpty {
            let best = videos.max { ($0["width"].int ?? 0) * ($0["height"].int ?? 0) < ($1["width"].int ?? 0) * ($1["height"].int ?? 0) }
            guard let best, let url = best["url"].url else { return nil }
            return GalleryItem(id: mediaID, kind: .video, url: url, thumbnail: thumbnail, width: best["width"].int, height: best["height"].int, headers: mediaHeaders, suggestedName: name, takenAt: takenAt)
        }
        if let videoURL = media["video_url"].url {
            return GalleryItem(id: mediaID, kind: .video, url: videoURL, thumbnail: media["display_url"].url ?? thumbnail, width: media["dimensions"]["width"].int, height: media["dimensions"]["height"].int, headers: mediaHeaders, suggestedName: name, takenAt: takenAt)
        }
        if let bestImage, let url = bestImage["url"].url {
            return GalleryItem(id: mediaID, kind: .photo, url: url, thumbnail: thumbnail, width: bestImage["width"].int, height: bestImage["height"].int, headers: mediaHeaders, suggestedName: name, takenAt: takenAt)
        }
        if let display = media["display_url"].url {
            return GalleryItem(id: mediaID, kind: .photo, url: display, thumbnail: display, width: media["dimensions"]["width"].int, height: media["dimensions"]["height"].int, headers: mediaHeaders, suggestedName: name, takenAt: takenAt)
        }
        return nil
    }

    func embedLegacy(shortcode: String, url: URL) async throws -> Gallery? {
        let embedURL = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/")!
        let result = try await http.getOK(embedURL, headers: ["Accept": "text/html"])
        let html = result.text
        var media: J?
        if let context = TextScan.first(#""contextJSON":"((?:\\.|[^"\\])*)""#, in: html) {
            let unescaped = J(string: "\"\(context)\"").string ?? ""
            let json = J(string: unescaped)
            media = json["gql_data"]["shortcode_media"].exists ? json["gql_data"]["shortcode_media"] : nil
        }
        if media == nil, let additional = TextScan.first(#"window\.__additionalDataLoaded\('extra',\s*(\{.*?\})\);"#, in: html) {
            let json = J(string: additional)
            media = json["shortcode_media"].exists ? json["shortcode_media"] : nil
        }
        let base = FileNamer.sanitize("instagram \(shortcode)", maxLength: 80)
        var items: [GalleryItem] = []
        var username: String?
        if let media {
            username = media["owner"]["username"].nonEmptyString
            let nodes = media["edge_sidecar_to_children"]["edges"].array.map { $0["node"] }
            let all = nodes.isEmpty ? [media] : nodes
            for (index, node) in all.enumerated() {
                let suffix = all.count > 1 ? " \(index + 1)" : ""
                if node["is_video"].bool == true, let video = node["video_url"].url {
                    items.append(GalleryItem(id: "\(shortcode)-\(index)", kind: .video, url: video, thumbnail: node["display_url"].url, width: node["dimensions"]["width"].int, height: node["dimensions"]["height"].int, headers: InstagramClient.mediaHeaders, suggestedName: base + suffix))
                } else if let display = node["display_url"].url {
                    items.append(GalleryItem(id: "\(shortcode)-\(index)", kind: .photo, url: display, thumbnail: display, width: node["dimensions"]["width"].int, height: node["dimensions"]["height"].int, headers: InstagramClient.mediaHeaders, suggestedName: base + suffix))
                }
            }
        }
        if items.isEmpty, let image = TextScan.first(#"class="EmbeddedMediaImage"[^>]*src="([^"]+)""#, in: html) ?? TextScan.first(#"<img[^>]*class="EmbeddedMediaImage"[^>]*src="([^"]+)""#, in: html) {
            let decoded = TextScan.decodeHTMLEntities(image)
            if let imageURL = URL(string: decoded) {
                items.append(GalleryItem(id: "\(shortcode)-0", kind: .photo, url: imageURL, thumbnail: imageURL, headers: InstagramClient.mediaHeaders, suggestedName: base))
            }
        }
        guard !items.isEmpty else { return nil }
        if items.count == 1, items[0].kind == .video {
            items[0].ytdlpURL = url.absoluteString
        }
        let caption = media?["edge_media_to_caption"]["edges"][0]["node"]["text"].nonEmptyString
        let summary = MediaSummary(
            title: InstagramClient.titleFrom(caption: caption, fallback: username.map { "Post by @\($0)" } ?? "Instagram post"),
            author: username.map { "@\($0)" },
            thumbnail: items.first?.thumbnail,
            platform: .instagram,
            webpageURL: url
        )
        return Gallery(summary: summary, sections: [GallerySection(id: "post", title: items.count == 1 ? (items[0].kind == .video ? "Video" : "Photo") : "\(items.count) items", items: items)], folderName: base, isProfile: false)
    }

    public struct Profile: Sendable {
        public var id: String
        public var username: String
        public var fullName: String?
        public var pictureURL: URL?
        public var isPrivate: Bool
        public var followers: Int?
        public var posts: Int?
    }

    public func fetchProfile(username: String) async throws -> Profile {
        var profile: Profile?
        do {
            let json = try await api("users/web_profile_info/?username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)")
            let user = json["data"]["user"]
            if user.exists, let id = user["id"].string {
                profile = Profile(
                    id: id,
                    username: user["username"].string ?? username,
                    fullName: user["full_name"].nonEmptyString,
                    pictureURL: user["profile_pic_url_hd"].url ?? user["profile_pic_url"].url,
                    isPrivate: user["is_private"].bool ?? false,
                    followers: user["edge_followed_by"]["count"].int,
                    posts: user["edge_owner_to_timeline_media"]["count"].int
                )
            }
        } catch {
            if error.isCancellation { throw error }
            if let known = error as? DownlyError, case .unavailable = known { throw known }
        }
        if profile == nil {
            profile = try await profileFromPage(username: username)
        }
        guard var resolved = profile else {
            throw DownlyError.unavailable("Couldn’t find @\(username) on Instagram.")
        }
        if isLoggedIn, let json = try? await api("users/\(resolved.id)/info/") {
            let user = json["user"]
            if let hd = user["hd_profile_pic_url_info"]["url"].url {
                resolved.pictureURL = hd
            } else if let best = user["hd_profile_pic_versions"].array.max(by: { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) })?["url"].url {
                resolved.pictureURL = best
            }
        }
        return resolved
    }

    func profileFromPage(username: String) async throws -> Profile? {
        let url = URL(string: "https://www.instagram.com/\(username)/")!
        let result = try await http.get(url, headers: ["Accept": "text/html"])
        guard result.isSuccess else {
            if result.status == 404 { throw DownlyError.unavailable("Couldn’t find @\(username) on Instagram.") }
            return nil
        }
        let html = result.text
        let id = TextScan.first(#""profilePage_(\d+)""#, in: html) ?? TextScan.first(#""user_id":"(\d+)""#, in: html) ?? TextScan.first(#""id":"(\d+)","username":""#, in: html) ?? ""
        let picture = TextScan.first(#""profile_pic_url_hd":"([^"]+)""#, in: html).flatMap { J(string: "\"\($0)\"").string }.flatMap(URL.init(string:))
            ?? TextScan.metaContent("og:image", in: html).flatMap(URL.init(string:))
        guard picture != nil || !id.isEmpty else { return nil }
        let title = TextScan.metaContent("og:title", in: html)
        let fullName = title?.components(separatedBy: " (@").first
        return Profile(id: id, username: username, fullName: fullName, pictureURL: picture, isPrivate: false, followers: nil, posts: nil)
    }

    public func profileGallery(username: String, url: URL) async throws -> Gallery {
        let profile = try await fetchProfile(username: username)
        var sections: [GallerySection] = []
        if let picture = profile.pictureURL {
            let item = GalleryItem(id: "pfp-\(profile.id)", kind: .photo, url: picture, thumbnail: picture, headers: InstagramClient.mediaHeaders, suggestedName: FileNamer.sanitize("\(profile.username) profile picture"))
            sections.append(GallerySection(id: "pfp", title: "Profile picture", items: [item]))
        }
        if isLoggedIn, !profile.id.isEmpty, let stories = try? await reelItems(reelID: profile.id, username: profile.username), !stories.isEmpty {
            sections.append(GallerySection(id: "stories", title: "Stories", items: stories))
        }
        guard !sections.isEmpty else { throw DownlyError.nothingToDownload }
        var details: [String] = []
        if let followers = profile.followers {
            details.append("\(InstagramClient.compact(followers)) followers")
        }
        let summary = MediaSummary(
            title: profile.fullName ?? "@\(profile.username)",
            author: "@\(profile.username)" + (details.isEmpty ? "" : " · " + details.joined(separator: " · ")),
            thumbnail: profile.pictureURL,
            platform: .instagram,
            webpageURL: url
        )
        return Gallery(summary: summary, sections: sections, folderName: FileNamer.sanitize("\(profile.username) instagram"), isProfile: true)
    }

    public func stories(username: String, storyID: String?, url: URL) async throws -> Gallery {
        guard isLoggedIn else {
            throw DownlyError.needsLogin(.instagram, "Instagram only shows stories to signed-in people.")
        }
        let profile = try await fetchProfile(username: username)
        let items = try await reelItems(reelID: profile.id, username: username)
        guard !items.isEmpty else {
            throw DownlyError.unavailable("@\(username) has no active stories right now.")
        }
        var sections: [GallerySection] = []
        if let storyID, let match = items.first(where: { $0.id == storyID || $0.id.hasPrefix(storyID + "_") }) {
            sections.append(GallerySection(id: "story", title: "This story", items: [match]))
            let others = items.filter { $0.id != match.id }
            if !others.isEmpty {
                sections.append(GallerySection(id: "stories", title: "All stories", items: others))
            }
        } else {
            sections.append(GallerySection(id: "stories", title: "\(items.count) \(items.count == 1 ? "story" : "stories")", items: items))
        }
        let summary = MediaSummary(
            title: "Stories by @\(username)",
            author: profile.fullName,
            thumbnail: profile.pictureURL ?? items.first?.thumbnail,
            platform: .instagram,
            webpageURL: url
        )
        return Gallery(summary: summary, sections: sections, folderName: FileNamer.sanitize("\(username) stories"), isProfile: false)
    }

    public func highlight(id: String, url: URL) async throws -> Gallery {
        guard isLoggedIn else {
            throw DownlyError.needsLogin(.instagram, "Instagram only shows highlights to signed-in people.")
        }
        let reelID = "highlight:\(id)"
        let json = try await api("feed/reels_media/?reel_ids=\(reelID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? reelID)")
        let reel = json["reels"][reelID].exists ? json["reels"][reelID] : json["reels_media"][0]
        let username = reel["user"]["username"].string ?? "instagram"
        let title = reel["title"].nonEmptyString ?? "Highlight"
        let items = InstagramClient.storyItems(reel["items"].array, username: username)
        guard !items.isEmpty else { throw DownlyError.nothingToDownload }
        let summary = MediaSummary(
            title: title,
            author: "@\(username)",
            thumbnail: reel["cover_media"]["cropped_image_version"]["url"].url ?? items.first?.thumbnail,
            platform: .instagram,
            webpageURL: url
        )
        return Gallery(summary: summary, sections: [GallerySection(id: "highlight", title: "\(items.count) items", items: items)], folderName: FileNamer.sanitize("\(username) \(title)"), isProfile: false)
    }

    func reelItems(reelID: String, username: String) async throws -> [GalleryItem] {
        let json = try await api("feed/reels_media/?reel_ids=\(reelID)")
        let reel = json["reels"][reelID].exists ? json["reels"][reelID] : json["reels_media"][0]
        return InstagramClient.storyItems(reel["items"].array, username: username)
    }

    static func storyItems(_ raw: [J], username: String) -> [GalleryItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        var items: [GalleryItem] = []
        for (index, media) in raw.enumerated() {
            let takenAt = media["taken_at"].double.map { Date(timeIntervalSince1970: $0) }
            let stamp = takenAt.map { formatter.string(from: $0) } ?? "\(index + 1)"
            let pk = media["pk"].string ?? media["id"].string ?? "\(index)"
            if var item = item(from: media, id: pk, name: FileNamer.sanitize("\(username) story \(stamp)")) {
                item.id = pk
                items.append(item)
            }
        }
        return items
    }

    static func compact(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        if value >= 1_000_000 {
            return (formatter.string(from: NSNumber(value: Double(value) / 1_000_000)) ?? "") + "M"
        }
        if value >= 10_000 {
            return (formatter.string(from: NSNumber(value: Double(value) / 1_000)) ?? "") + "K"
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
