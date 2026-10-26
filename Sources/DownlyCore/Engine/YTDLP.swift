import Foundation

public struct YTDLPProgress: Sendable {
    public var status: String
    public var downloaded: Int64?
    public var total: Int64?
    public var speed: Double?
    public var eta: Double?
    public var formatID: String?
    public var fragmentIndex: Int?
    public var fragmentCount: Int?
}

public enum YTDLPEvent: Sendable {
    case progress(YTDLPProgress)
    case postprocess(name: String, status: String)
    case file(String)
    case log(String)
}

public struct YTDLP: Sendable {
    public let tools: ToolPaths
    public let cookieBrowser: CookieBrowser?

    public init(tools: ToolPaths, cookieBrowser: CookieBrowser? = nil) {
        self.tools = tools
        self.cookieBrowser = cookieBrowser
    }

    static let progressTemplate = "download:DLYP|%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.format_id)s|%(progress.fragment_index)s|%(progress.fragment_count)s"
    static let postprocessTemplate = "postprocess:DLYPP|%(progress.status)s|%(progress.postprocessor)s"

    func baseArguments(useCookies: Bool) -> [String] {
        var args = [
            "--ignore-config",
            "--no-color",
            "--no-warnings",
            "--ffmpeg-location", tools.ffmpegDirectory.path,
            "--js-runtimes", "deno:\(tools.deno.path)",
            "--cache-dir", AppPaths.ytdlpCache.path,
            "--socket-timeout", "30",
            "--retries", "5",
            "--fragment-retries", "10",
            "--extractor-retries", "3",
        ]
        if useCookies, let cookieBrowser {
            args += ["--cookies-from-browser", cookieBrowser.ytdlpName]
        }
        return args
    }

    public func extractInfo(_ url: String, playlist: Bool, useCookies: Bool, flat: Bool = false, extra: [String] = []) async throws -> J {
        var args = baseArguments(useCookies: useCookies)
        args += ["-J", "--skip-download"]
        args += playlist ? ["--yes-playlist", "--flat-playlist", "--playlist-end", "1000"] : ["--no-playlist"]
        if flat && !playlist {
            args += ["--flat-playlist"]
        }
        args += extra
        args.append(url)
        let result = try await ProcessRunner.run(tools.ytdlp, args)
        let json = J(string: result.stdout)
        if json.exists, json["id"].exists || json["entries"].exists || json["title"].exists {
            return json
        }
        throw YTDLP.interpretError(result.stderr, status: result.status)
    }

    public func run(arguments: [String], url: String, useCookies: Bool, onEvent: @escaping @Sendable (YTDLPEvent) -> Void) async throws -> [String] {
        var args = baseArguments(useCookies: useCookies)
        args += [
            "--newline",
            "--progress",
            "--progress-template", YTDLP.progressTemplate,
            "--progress-template", YTDLP.postprocessTemplate,
            "--print", "after_move:DLYF|%(filepath)s",
            "--no-mtime",
            "--concurrent-fragments", "4",
        ]
        args += arguments
        args.append(url)
        let files = FileCollector()
        let result = try await ProcessRunner.run(tools.ytdlp, args) { line, _ in
            if let event = YTDLP.parse(line: line) {
                if case .file(let path) = event {
                    files.append(path)
                }
                onEvent(event)
            }
        }
        let produced = files.values.filter { FileManager.default.fileExists(atPath: $0) }
        if result.succeeded, !produced.isEmpty {
            return produced
        }
        if !produced.isEmpty, !result.stderr.contains("ERROR:") {
            return produced
        }
        throw YTDLP.interpretError(result.stderr, status: result.status)
    }

    public static func parse(line: String) -> YTDLPEvent? {
        if line.hasPrefix("DLYP|") {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 10 else { return nil }
            func int64(_ value: String) -> Int64? {
                if let number = Int64(value) { return number }
                if let double = Double(value) { return Int64(double) }
                return nil
            }
            let total = int64(parts[3]) ?? int64(parts[4])
            return .progress(YTDLPProgress(
                status: parts[1],
                downloaded: int64(parts[2]),
                total: total,
                speed: Double(parts[5]),
                eta: Double(parts[6]),
                formatID: parts[7] == "NA" ? nil : parts[7],
                fragmentIndex: Int(parts[8]),
                fragmentCount: Int(parts[9])
            ))
        }
        if line.hasPrefix("DLYPP|") {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { return nil }
            return .postprocess(name: parts[2], status: parts[1])
        }
        if line.hasPrefix("DLYF|") {
            return .file(String(line.dropFirst(5)))
        }
        return .log(line)
    }

    public static func interpretError(_ stderr: String, status: Int32) -> DownlyError {
        let lines = stderr.split(whereSeparator: \.isNewline).map(String.init)
        let errorLine = lines.last { $0.hasPrefix("ERROR:") } ?? lines.last { $0.contains("ERROR") } ?? ""
        var message = errorLine.replacingOccurrences(of: "ERROR: ", with: "")
        if let range = message.range(of: #"^\[[^\]]+\] [^:]+: "#, options: .regularExpression) {
            message.removeSubrange(range)
        }
        let lower = stderr.lowercased()
        if lower.contains("sign in to confirm") || lower.contains("not a bot") {
            return .botCheck
        }
        if lower.contains("instagram") && (lower.contains("login") || lower.contains("log in") || lower.contains("rate-limit") || lower.contains("cookies")) {
            return .needsLogin(.instagram, "Instagram wants you to be signed in to view this.")
        }
        if lower.contains("private video") || lower.contains("this video is private") {
            return .unavailable("This video is private.")
        }
        if lower.contains("sign in to confirm your age") || lower.contains("age-restricted") || lower.contains("inappropriate for some users") {
            return .needsLogin(.youtube, "This video is age-restricted.")
        }
        if lower.contains("members-only") || lower.contains("join this channel") {
            return .unavailable("This video is for channel members only.")
        }
        if lower.contains("unsupported url") {
            return .unsupportedLink
        }
        if lower.contains("video unavailable") || lower.contains("has been removed") || lower.contains("not available") || lower.contains("404") {
            return .unavailable(message.isEmpty ? "This content isn’t available." : message)
        }
        if lower.contains("unable to download webpage") || lower.contains("timed out") || lower.contains("connection") || lower.contains("network is unreachable") || lower.contains("name or service not known") || lower.contains("nodename nor servname") {
            return .network("Couldn’t connect. Check your internet connection.")
        }
        if lower.contains("drm") {
            return .unavailable("This content is DRM-protected and can’t be downloaded.")
        }
        if lower.contains("requested format is not available") {
            return .unavailable("That quality isn’t available anymore. Try another one.")
        }
        if message.isEmpty {
            let tail = lines.suffix(2).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return .toolFailed(tail.isEmpty ? "The download engine stopped unexpectedly (code \(status))." : tail)
        }
        return .message(message)
    }
}

final class FileCollector: @unchecked Sendable {
    private var items: [String] = []
    private let lock = NSLock()

    func append(_ value: String) {
        lock.lock()
        if !items.contains(value) {
            items.append(value)
        }
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
