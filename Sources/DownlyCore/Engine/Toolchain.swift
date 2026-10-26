import Foundation

public enum ToolID: String, CaseIterable, Sendable, Codable, Hashable {
    case ytdlp
    case ffmpeg
    case ffprobe
    case deno

    public var displayName: String {
        switch self {
        case .ytdlp: return "yt-dlp"
        case .ffmpeg: return "FFmpeg"
        case .ffprobe: return "FFprobe"
        case .deno: return "Deno"
        }
    }

    public var purpose: String {
        switch self {
        case .ytdlp: return "Download engine"
        case .ffmpeg: return "Merging & converting"
        case .ffprobe: return "Media inspection"
        case .deno: return "YouTube signature solver"
        }
    }
}

public struct ToolPaths: Sendable, Hashable {
    public var ytdlp: URL
    public var ffmpeg: URL
    public var ffprobe: URL
    public var deno: URL

    public var ffmpegDirectory: URL {
        ffmpeg.deletingLastPathComponent()
    }
}

public enum ToolInstallPhase: Sendable, Equatable {
    case waiting
    case downloading(Double)
    case installing
    case ready(String)
    case failed(String)
}

public struct ToolchainManifest: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var path: String
        public var version: String
        public var source: String
    }

    public var tools: [String: Entry] = [:]
    public var lastYTDLPCheck: Date?
}

public actor Toolchain {
    public static let shared = Toolchain()

    private var manifest: ToolchainManifest
    private let root: URL
    private let http = HTTPClient(userAgent: UserAgent.safari, timeout: 30, storesCookies: false)

    public init(root: URL = AppPaths.tools) {
        self.root = root
        let url = root.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(ToolchainManifest.self, from: data) {
            manifest = decoded
        } else {
            manifest = ToolchainManifest()
        }
    }

    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public func paths() -> ToolPaths? {
        guard let ytdlp = resolved(.ytdlp), let ffmpeg = resolved(.ffmpeg), let ffprobe = resolved(.ffprobe), let deno = resolved(.deno) else {
            return nil
        }
        return ToolPaths(ytdlp: ytdlp, ffmpeg: ffmpeg, ffprobe: ffprobe, deno: deno)
    }

    public func versions() -> [ToolID: String] {
        var output: [ToolID: String] = [:]
        for tool in ToolID.allCases {
            if let entry = manifest.tools[tool.rawValue], resolved(tool) != nil {
                output[tool] = entry.version
            }
        }
        return output
    }

    public func missingTools() -> [ToolID] {
        ToolID.allCases.filter { resolved($0) == nil }
    }

    private func resolved(_ tool: ToolID) -> URL? {
        guard let entry = manifest.tools[tool.rawValue] else { return nil }
        let url = entry.path.hasPrefix("/") ? URL(fileURLWithPath: entry.path) : root.appendingPathComponent(entry.path)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func saveManifest() {
        let url = root.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func record(_ tool: ToolID, path: URL, version: String, source: String) {
        let relative: String
        if path.path.hasPrefix(root.path + "/") {
            relative = String(path.path.dropFirst(root.path.count + 1))
        } else {
            relative = path.path
        }
        manifest.tools[tool.rawValue] = ToolchainManifest.Entry(path: relative, version: version, source: source)
        saveManifest()
    }

    public func install(
        tools requested: [ToolID]? = nil,
        progress: @escaping @Sendable (ToolID, ToolInstallPhase) -> Void
    ) async throws -> ToolPaths {
        let wanted = requested ?? missingTools()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var failures: [String] = []
        await withTaskGroup(of: (ToolID, Result<(URL, String, String), Error>).self) { group in
            for tool in wanted {
                progress(tool, .waiting)
                group.addTask { [root] in
                    do {
                        let result = try await Toolchain.installTool(tool, root: root) { fraction in
                            progress(tool, .downloading(fraction))
                        } phase: { phase in
                            progress(tool, phase)
                        }
                        return (tool, .success(result))
                    } catch {
                        return (tool, .failure(error))
                    }
                }
            }
            for await (tool, result) in group {
                switch result {
                case .success(let (path, version, source)):
                    record(tool, path: path, version: version, source: source)
                    progress(tool, .ready(version))
                case .failure(let error):
                    if let fallback = Toolchain.systemFallback(for: tool), let version = try? await Toolchain.verify(tool, at: fallback) {
                        record(tool, path: fallback, version: version, source: "system")
                        progress(tool, .ready(version))
                    } else {
                        failures.append("\(tool.displayName): \(error.friendlyMessage)")
                        progress(tool, .failed(error.friendlyMessage))
                    }
                }
            }
        }
        if !failures.isEmpty {
            throw DownlyError.toolFailed(failures.joined(separator: "\n"))
        }
        guard let paths = paths() else {
            throw DownlyError.toolMissing("Download engine")
        }
        cleanupStaleVersions()
        return paths
    }

    public func ensureInstalled(progress: @escaping @Sendable (ToolID, ToolInstallPhase) -> Void) async throws -> ToolPaths {
        if let paths = paths() {
            return paths
        }
        return try await install(progress: progress)
    }

    public func reinstallAll(progress: @escaping @Sendable (ToolID, ToolInstallPhase) -> Void) async throws -> ToolPaths {
        try await install(tools: ToolID.allCases, progress: progress)
    }

    public func latestYTDLPVersion() async -> String? {
        guard let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest") else { return nil }
        let final = await http.finalURL(for: url)
        let tag = final.lastPathComponent
        guard tag.first?.isNumber == true else { return nil }
        return tag
    }

    public func updateYTDLPIfNeeded(force: Bool = false, progress: (@Sendable (ToolInstallPhase) -> Void)? = nil) async -> String? {
        if !force, let last = manifest.lastYTDLPCheck, Date().timeIntervalSince(last) < 60 * 60 * 20 {
            return nil
        }
        guard let latest = await latestYTDLPVersion() else { return nil }
        manifest.lastYTDLPCheck = Date()
        saveManifest()
        let current = manifest.tools[ToolID.ytdlp.rawValue]?.version ?? ""
        guard resolved(.ytdlp) == nil || current.compare(latest, options: .numeric) == .orderedAscending else {
            return nil
        }
        do {
            let (path, version, source) = try await Toolchain.installTool(.ytdlp, root: root) { fraction in
                progress?(.downloading(fraction))
            } phase: { phase in
                progress?(phase)
            }
            record(.ytdlp, path: path, version: version, source: source)
            progress?(.ready(version))
            cleanupStaleVersions()
            return version
        } catch {
            progress?(.failed(error.friendlyMessage))
            return nil
        }
    }

    private func cleanupStaleVersions() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        let inUse = Set(manifest.tools.values.map { $0.path.split(separator: "/").first.map(String.init) ?? $0.path })
        for item in contents {
            let name = item.lastPathComponent
            if name == "manifest.json" || inUse.contains(name) { continue }
            if name.hasPrefix("yt-dlp-") || name.hasPrefix("ffmpeg-") || name.hasPrefix("ffprobe-") || name.hasPrefix("deno-") || name.hasSuffix(".partial") {
                try? fm.removeItem(at: item)
            }
        }
    }

    static func systemFallback(for tool: ToolID) -> URL? {
        let names: [String]
        switch tool {
        case .ytdlp: names = ["yt-dlp"]
        case .ffmpeg: names = ["ffmpeg"]
        case .ffprobe: names = ["ffprobe"]
        case .deno: names = ["deno"]
        }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            for name in names {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    static func sources(for tool: ToolID) -> [(url: String, kind: ArchiveKind, binary: String)] {
        let arm = isAppleSilicon
        switch tool {
        case .ytdlp:
            return [
                ("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip", .zip, "yt-dlp_macos"),
                ("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos", .raw, "yt-dlp_macos"),
            ]
        case .ffmpeg:
            return [
                ("https://github.com/shaka-project/static-ffmpeg-binaries/releases/latest/download/ffmpeg-osx-\(arm ? "arm64" : "x64")", .raw, "ffmpeg"),
                ("https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arm ? "arm64" : "amd64")/release/ffmpeg.zip", .zip, "ffmpeg"),
            ]
        case .ffprobe:
            return [
                ("https://github.com/shaka-project/static-ffmpeg-binaries/releases/latest/download/ffprobe-osx-\(arm ? "arm64" : "x64")", .raw, "ffprobe"),
                ("https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arm ? "arm64" : "amd64")/release/ffprobe.zip", .zip, "ffprobe"),
            ]
        case .deno:
            return [
                ("https://github.com/denoland/deno/releases/latest/download/deno-\(arm ? "aarch64" : "x86_64")-apple-darwin.zip", .zip, "deno"),
                ("https://dl.deno.land/release/v2.5.6/deno-\(arm ? "aarch64" : "x86_64")-apple-darwin.zip", .zip, "deno"),
            ]
        }
    }

    enum ArchiveKind {
        case raw
        case zip
    }

    static func installTool(
        _ tool: ToolID,
        root: URL,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        phase: @escaping @Sendable (ToolInstallPhase) -> Void
    ) async throws -> (URL, String, String) {
        let fm = FileManager.default
        var lastError: Error = DownlyError.toolMissing(tool.displayName)
        for source in sources(for: tool) {
            try Task.checkCancellation()
            guard let url = URL(string: source.url) else { continue }
            let stamp = String(Int(Date().timeIntervalSince1970))
            let folderName = "\(tool == .ytdlp ? "yt-dlp" : tool.rawValue)-\(stamp)"
            let work = root.appendingPathComponent(folderName + ".partial", isDirectory: true)
            let final = root.appendingPathComponent(folderName, isDirectory: true)
            try? fm.removeItem(at: work)
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let downloadTarget = work.appendingPathComponent(source.kind == .zip ? "archive.zip" : source.binary)
                try await FileDownloader.download(url, to: downloadTarget) { received, expected in
                    if let expected, expected > 0 {
                        downloadProgress(min(1, Double(received) / Double(expected)))
                    }
                }
                phase(.installing)
                var binary: URL
                if source.kind == .zip {
                    let extracted = work.appendingPathComponent("contents", isDirectory: true)
                    try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
                    let unzip = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", downloadTarget.path, extracted.path])
                    guard unzip.succeeded else {
                        throw DownlyError.toolFailed("Couldn’t unpack \(tool.displayName).")
                    }
                    try? fm.removeItem(at: downloadTarget)
                    guard let found = findExecutable(named: source.binary, in: extracted) else {
                        throw DownlyError.toolFailed("\(tool.displayName) archive looked different than expected.")
                    }
                    binary = found
                } else {
                    binary = downloadTarget
                }
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
                _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", work.path])
                var version: String
                do {
                    version = try await verify(tool, at: binary)
                } catch {
                    _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "--deep", "--sign", "-", binary.path])
                    version = try await verify(tool, at: binary)
                }
                try? fm.removeItem(at: final)
                try fm.moveItem(at: work, to: final)
                let relative = String(binary.path.dropFirst(work.path.count + 1))
                return (final.appendingPathComponent(relative), version, url.host ?? "web")
            } catch {
                try? fm.removeItem(at: work)
                if error.isCancellation { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    static func findExecutable(named name: String, in directory: URL) -> URL? {
        let fm = FileManager.default
        let direct = directory.appendingPathComponent(name)
        if fm.isExecutableFile(atPath: direct.path) || fm.fileExists(atPath: direct.path) {
            return direct
        }
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]) else {
            return nil
        }
        var best: URL?
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if best == nil || url.pathComponents.count < best!.pathComponents.count {
                best = url
            }
        }
        return best
    }

    static func verify(_ tool: ToolID, at url: URL) async throws -> String {
        let args: [String]
        switch tool {
        case .ytdlp: args = ["--version"]
        case .ffmpeg, .ffprobe: args = ["-hide_banner", "-version"]
        case .deno: args = ["--version"]
        }
        let result = try await ProcessRunner.output(url, args, timeout: 120)
        guard result.succeeded else {
            let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? "exit \(result.status)"
            throw DownlyError.toolFailed("\(tool.displayName) didn’t start (\(detail)).")
        }
        let firstLine = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        switch tool {
        case .ytdlp:
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .ffmpeg, .ffprobe:
            let parts = firstLine.split(separator: " ")
            if let index = parts.firstIndex(of: "version"), index + 1 < parts.count {
                return String(parts[index + 1])
            }
            return firstLine
        case .deno:
            let parts = firstLine.split(separator: " ")
            return parts.count > 1 ? String(parts[1]) : firstLine
        }
    }
}
