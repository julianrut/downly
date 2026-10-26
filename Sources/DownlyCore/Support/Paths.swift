import Foundation

public enum AppPaths {
    public static let appName = "Downly"

    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return ensure(base.appendingPathComponent(appName, isDirectory: true))
    }

    public static var tools: URL {
        if let override = ProcessInfo.processInfo.environment["DOWNLY_TOOLS_DIR"], !override.isEmpty {
            return ensure(URL(fileURLWithPath: override, isDirectory: true))
        }
        return ensure(support.appendingPathComponent("Tools", isDirectory: true))
    }

    public static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return ensure(base.appendingPathComponent(appName, isDirectory: true))
    }

    public static var ytdlpCache: URL {
        ensure(caches.appendingPathComponent("yt-dlp", isDirectory: true))
    }

    public static var staging: URL {
        ensure(caches.appendingPathComponent("Staging", isDirectory: true))
    }

    public static func stagingDirectory(for id: UUID) -> URL {
        ensure(staging.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    public static var history: URL {
        support.appendingPathComponent("History.json")
    }

    public static var defaultDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    @discardableResult
    public static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func cleanStaging() {
        try? FileManager.default.removeItem(at: staging)
    }
}

public enum FileNamer {
    public static func sanitize(_ raw: String, maxLength: Int = 140, fallback: String = "Download") -> String {
        var text = raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        text = text.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "\\", with: "-")
        text = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-").union(.whitespacesAndNewlines))
        if text.count > maxLength {
            text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
            if let lastSpace = text.lastIndex(of: " "), text.distance(from: text.startIndex, to: lastSpace) > maxLength / 2 {
                text = String(text[..<lastSpace])
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-,"))
        }
        return text.isEmpty ? fallback : text
    }

    public static func uniqueURL(in directory: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        func make(_ name: String) -> URL {
            cleanExt.isEmpty
                ? directory.appendingPathComponent(name)
                : directory.appendingPathComponent(name).appendingPathExtension(cleanExt)
        }
        var candidate = make(base)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(counter)")
            counter += 1
        }
        return candidate
    }

    public static func uniqueDirectory(in parent: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(counter)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    public static func move(_ file: URL, into directory: URL, name: String? = nil) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = file.pathExtension
        let base = sanitize(name ?? file.deletingPathExtension().lastPathComponent)
        let destination = uniqueURL(in: directory, base: base, ext: ext)
        do {
            try fm.moveItem(at: file, to: destination)
        } catch {
            try fm.copyItem(at: file, to: destination)
            try? fm.removeItem(at: file)
        }
        return destination
    }
}
