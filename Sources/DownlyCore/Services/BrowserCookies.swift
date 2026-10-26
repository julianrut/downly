import Foundation

public enum CookieBrowser: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case safari
    case chrome
    case firefox
    case brave
    case edge
    case opera
    case vivaldi
    case chromium

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .firefox: return "Firefox"
        case .brave: return "Brave"
        case .edge: return "Microsoft Edge"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .chromium: return "Chromium"
        }
    }

    public var applicationPaths: [String] {
        switch self {
        case .safari: return ["/Applications/Safari.app", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"]
        case .chrome: return ["/Applications/Google Chrome.app"]
        case .firefox: return ["/Applications/Firefox.app"]
        case .brave: return ["/Applications/Brave Browser.app"]
        case .edge: return ["/Applications/Microsoft Edge.app"]
        case .opera: return ["/Applications/Opera.app"]
        case .vivaldi: return ["/Applications/Vivaldi.app"]
        case .chromium: return ["/Applications/Chromium.app"]
        }
    }

    public var isInstalled: Bool {
        if self == .safari { return true }
        let home = NSHomeDirectory()
        return applicationPaths.contains { path in
            FileManager.default.fileExists(atPath: path) || FileManager.default.fileExists(atPath: home + path)
        }
    }

    public var ytdlpName: String { rawValue }
}

public struct BrowserCookieSnapshot: Sendable {
    public let browser: CookieBrowser
    public let cookies: [HTTPCookie]
    public let date: Date

    public func cookies(forDomain domain: String) -> [HTTPCookie] {
        cookies.filter { cookie in
            let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return cookieDomain == domain || cookieDomain.hasSuffix("." + domain) || domain.hasSuffix("." + cookieDomain)
        }
    }

    public func value(_ name: String, domain: String) -> String? {
        cookies(forDomain: domain).first { $0.name == name }?.value
    }

    public func headerValue(forDomain domain: String) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for cookie in cookies(forDomain: domain) where !seen.contains(cookie.name) {
            seen.insert(cookie.name)
            parts.append("\(cookie.name)=\(cookie.value)")
        }
        return parts.joined(separator: "; ")
    }
}

public actor BrowserCookies {
    public static let shared = BrowserCookies()

    private var cache: [CookieBrowser: BrowserCookieSnapshot] = [:]
    private let keepDomains = ["instagram.com", "tiktok.com"]

    public func snapshot(for browser: CookieBrowser, ytdlp: URL, forceRefresh: Bool = false) async throws -> BrowserCookieSnapshot {
        if !forceRefresh, let cached = cache[browser], Date().timeIntervalSince(cached.date) < 20 * 60 {
            return cached
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("downly-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("cookies.txt")
        let result = try await ProcessRunner.run(ytdlp, [
            "--ignore-config", "--no-warnings",
            "--cookies-from-browser", browser.ytdlpName,
            "--cookies", file.path,
        ])
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw BrowserCookies.explain(result.stderr, browser: browser)
        }
        let all = BrowserCookies.parseNetscape(text)
        let kept = all.filter { cookie in
            keepDomains.contains { domain in cookie.domain.hasSuffix(domain) }
        }
        if all.isEmpty {
            throw BrowserCookies.explain(result.stderr, browser: browser)
        }
        let snapshot = BrowserCookieSnapshot(browser: browser, cookies: kept, date: Date())
        cache[browser] = snapshot
        return snapshot
    }

    public func invalidate() {
        cache.removeAll()
    }

    static func explain(_ stderr: String, browser: CookieBrowser) -> DownlyError {
        let lower = stderr.lowercased()
        if browser == .safari && (lower.contains("operation not permitted") || lower.contains("permission")) {
            return .message("Downly needs Full Disk Access to read Safari’s sign-in. Turn it on in System Settings → Privacy & Security → Full Disk Access, or pick another browser.")
        }
        if lower.contains("could not find") || lower.contains("no such file") {
            return .message("Couldn’t find \(browser.displayName)’s profile on this Mac.")
        }
        if lower.contains("keyring") || lower.contains("keychain") || lower.contains("decrypt") {
            return .message("macOS didn’t allow reading \(browser.displayName)’s cookies. Choose “Always Allow” when asked for keychain access.")
        }
        let line = stderr.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init) ?? ""
        return .message(line.isEmpty ? "Couldn’t read cookies from \(browser.displayName)." : line.replacingOccurrences(of: "ERROR: ", with: ""))
    }

    public static func parseNetscape(_ text: String) -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            var httpOnly = false
            if line.hasPrefix("#HttpOnly_") {
                line = String(line.dropFirst("#HttpOnly_".count))
                httpOnly = true
            } else if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 7 else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: fields[0],
                .path: fields[2].isEmpty ? "/" : fields[2],
                .name: fields[5],
                .value: fields[6],
            ]
            if fields[3].uppercased() == "TRUE" {
                properties[.secure] = "TRUE"
            }
            if let expiry = TimeInterval(fields[4]), expiry > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expiry)
            }
            if httpOnly {
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }
        return cookies
    }
}
