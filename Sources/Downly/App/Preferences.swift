import DownlyCore
import Foundation

enum PrefKey {
    static let downloadFolder = "downloadFolder"
    static let videoContainer = "videoContainer"
    static let appleCompatible = "appleCompatible"
    static let preferHDR = "preferHDR"
    static let defaultQuality = "defaultQuality"
    static let audioFormat = "audioFormat"
    static let musicFormat = "musicFormat"
    static let embedMetadata = "embedMetadata"
    static let filenameStyle = "filenameStyle"
    static let cookieBrowser = "cookieBrowser"
    static let alwaysUseCookies = "alwaysUseCookies"
    static let maxConcurrent = "maxConcurrent"
    static let notifications = "notifications"
    static let watchClipboard = "watchClipboard"
    static let autoUpdateEngine = "autoUpdateEngine"
    static let defaultMode = "defaultMode"
}

enum DownloadMode: String, CaseIterable, Identifiable {
    case video
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

struct Preferences {
    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.downloadFolder: AppPaths.defaultDownloads.path,
            PrefKey.videoContainer: VideoContainer.mp4.rawValue,
            PrefKey.appleCompatible: true,
            PrefKey.preferHDR: false,
            PrefKey.defaultQuality: 1080,
            PrefKey.audioFormat: AudioFormat.mp3.rawValue,
            PrefKey.musicFormat: AudioFormat.mp3.rawValue,
            PrefKey.embedMetadata: true,
            PrefKey.filenameStyle: FilenameStyle.title.rawValue,
            PrefKey.cookieBrowser: "",
            PrefKey.alwaysUseCookies: false,
            PrefKey.maxConcurrent: 3,
            PrefKey.notifications: true,
            PrefKey.watchClipboard: true,
            PrefKey.autoUpdateEngine: true,
            PrefKey.defaultMode: DownloadMode.video.rawValue,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var downloadFolder: URL {
        let path = defaults.string(forKey: PrefKey.downloadFolder) ?? AppPaths.defaultDownloads.path
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var videoContainer: VideoContainer {
        VideoContainer(rawValue: defaults.string(forKey: PrefKey.videoContainer) ?? "") ?? .mp4
    }

    static var appleCompatible: Bool {
        defaults.bool(forKey: PrefKey.appleCompatible)
    }

    static var videoPreferences: VideoPreferences {
        VideoPreferences(container: videoContainer, appleCompatible: appleCompatible && videoContainer == .mp4, preferHDR: defaults.bool(forKey: PrefKey.preferHDR))
    }

    static var defaultQuality: Int {
        defaults.integer(forKey: PrefKey.defaultQuality)
    }

    static var audioFormat: AudioFormat {
        AudioFormat(rawValue: defaults.string(forKey: PrefKey.audioFormat) ?? "") ?? .mp3
    }

    static var musicFormat: AudioFormat {
        AudioFormat(rawValue: defaults.string(forKey: PrefKey.musicFormat) ?? "") ?? .mp3
    }

    static var defaultMode: DownloadMode {
        DownloadMode(rawValue: defaults.string(forKey: PrefKey.defaultMode) ?? "") ?? .video
    }

    static var cookieBrowser: CookieBrowser? {
        CookieBrowser(rawValue: defaults.string(forKey: PrefKey.cookieBrowser) ?? "")
    }

    static var engineSettings: EngineSettings {
        EngineSettings(cookieBrowser: cookieBrowser, alwaysUseCookies: defaults.bool(forKey: PrefKey.alwaysUseCookies))
    }

    static var filenameStyle: FilenameStyle {
        FilenameStyle(rawValue: defaults.string(forKey: PrefKey.filenameStyle) ?? "") ?? .title
    }

    static var maxConcurrent: Int {
        min(max(defaults.integer(forKey: PrefKey.maxConcurrent), 1), 6)
    }

    static var embedMetadata: Bool {
        defaults.bool(forKey: PrefKey.embedMetadata)
    }

    static var notifications: Bool {
        defaults.bool(forKey: PrefKey.notifications)
    }

    static var watchClipboard: Bool {
        defaults.bool(forKey: PrefKey.watchClipboard)
    }

    static var autoUpdateEngine: Bool {
        defaults.bool(forKey: PrefKey.autoUpdateEngine)
    }
}
