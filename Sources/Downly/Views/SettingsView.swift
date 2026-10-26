import AppKit
import DownlyCore
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case formats
    case accounts
    case engine
}

struct SettingsView: View {
    @State var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            FormatSettings()
                .tabItem { Label("Formats", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.formats)
            AccountSettings()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            EngineSettingsView()
                .tabItem { Label("Engine", systemImage: "shippingbox") }
                .tag(SettingsTab.engine)
        }
        .frame(width: 560)
    }
}

struct GeneralSettings: View {
    @AppStorage(PrefKey.downloadFolder) var folder = AppPaths.defaultDownloads.path
    @AppStorage(PrefKey.maxConcurrent) var maxConcurrent = 3
    @AppStorage(PrefKey.filenameStyle) var filenameStyle = FilenameStyle.title
    @AppStorage(PrefKey.watchClipboard) var watchClipboard = true
    @AppStorage(PrefKey.notifications) var notifications = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Save downloads to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(displayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Stepper(value: $maxConcurrent, in: 1...6) {
                    LabeledContent("Simultaneous downloads", value: "\(maxConcurrent)")
                }
                Picker("File names", selection: $filenameStyle) {
                    ForEach(FilenameStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } header: {
                Text("Downloads")
            }
            Section {
                Toggle("Offer links I copy", isOn: $watchClipboard)
                Toggle("Notify me when downloads finish in the background", isOn: $notifications)
            } header: {
                Text("Convenience")
            } footer: {
                Text("When you switch to Downly with a supported link on your clipboard, it offers to grab it. Nothing leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 340)
    }

    var displayPath: String {
        (folder as NSString).abbreviatingWithTildeInPath
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}

struct FormatSettings: View {
    @AppStorage(PrefKey.defaultQuality) var defaultQuality = 1080
    @AppStorage(PrefKey.videoContainer) var container = VideoContainer.mp4
    @AppStorage(PrefKey.appleCompatible) var appleCompatible = true
    @AppStorage(PrefKey.preferHDR) var preferHDR = false
    @AppStorage(PrefKey.audioFormat) var audioFormat = AudioFormat.mp3
    @AppStorage(PrefKey.musicFormat) var musicFormat = AudioFormat.mp3
    @AppStorage(PrefKey.embedMetadata) var embedMetadata = true
    @AppStorage(PrefKey.defaultMode) var defaultMode = DownloadMode.video

    var body: some View {
        Form {
            Section {
                Picker("Start with", selection: $defaultMode) {
                    ForEach(DownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Preferred quality", selection: $defaultQuality) {
                    Text("Best available").tag(0)
                    ForEach([4320, 2160, 1440, 1080, 720, 480, 360], id: \.self) { tier in
                        Text(FormatPlanner.label(for: tier) + (tier >= 2160 ? " (\(FormatPlanner.caption(for: tier)))" : "")).tag(tier)
                    }
                }
                Picker("Container", selection: $container) {
                    ForEach(VideoContainer.allCases, id: \.self) { item in
                        Text(item == .mp4 ? "MP4 — works everywhere" : "MKV — keeps original streams").tag(item)
                    }
                }
                Toggle("Make every video play in QuickTime & Photos", isOn: $appleCompatible)
                    .disabled(container != .mp4)
                Toggle("Prefer HDR when available", isOn: $preferHDR)
            } header: {
                Text("Video")
            } footer: {
                Text("YouTube only offers 1440p, 4K and 8K as VP9 or AV1. With QuickTime compatibility on, Downly converts those to HEVC using your Mac’s media engine. Every video always includes sound.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Audio downloads", selection: $audioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { format in
                        Text("\(format.title) — \(format.detail)").tag(format)
                    }
                }
                Picker("Spotify songs", selection: $musicFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { format in
                        Text("\(format.title) — \(format.detail)").tag(format)
                    }
                }
                Toggle("Add cover art, title and artist", isOn: $embedMetadata)
            } header: {
                Text("Audio")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 460)
    }
}

struct AccountSettings: View {
    @Environment(AppModel.self) var model
    @AppStorage(PrefKey.cookieBrowser) var browserRaw = ""
    @AppStorage(PrefKey.alwaysUseCookies) var alwaysUseCookies = false
    @State var status: String?
    @State var statusIsGood = false
    @State var checking = false

    var browsers: [CookieBrowser] {
        CookieBrowser.allCases.filter { $0.isInstalled || $0.rawValue == browserRaw }
    }

    var body: some View {
        Form {
            Section {
                Picker("Use sign-in from", selection: $browserRaw) {
                    Text("Don’t use a browser").tag("")
                    Divider()
                    ForEach(browsers) { browser in
                        Text(browser.displayName).tag(browser.rawValue)
                    }
                }
                .onChange(of: browserRaw) {
                    status = nil
                    Task { await BrowserCookies.shared.invalidate() }
                }
                Toggle("Also use it for YouTube and other sites", isOn: $alwaysUseCookies)
                    .disabled(browserRaw.isEmpty)
                HStack {
                    Button(checking ? "Checking…" : "Check Instagram Sign-in", action: check)
                        .disabled(browserRaw.isEmpty || checking)
                    if let status {
                        Label(status, systemImage: statusIsGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(statusIsGood ? Color.green : Color.orange)
                            .font(.callout)
                            .lineLimit(3)
                    }
                }
            } header: {
                Text("Browser sign-in")
            } footer: {
                Text("Instagram stories, highlights, HD profile pictures and private posts need you to be signed in. Downly borrows the session from your browser on this Mac — your password is never seen or sent anywhere. YouTube also uses it when asking for age or bot checks.")
                    .foregroundStyle(.secondary)
            }
            if browserRaw == CookieBrowser.safari.rawValue {
                Section {
                    HStack {
                        Text("Safari keeps its cookies private. Give Downly Full Disk Access to use them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }

    func check() {
        guard let browser = CookieBrowser(rawValue: browserRaw), let tools = model.tools else {
            status = "Downly is still getting ready."
            statusIsGood = false
            return
        }
        checking = true
        status = nil
        Task {
            do {
                let snapshot = try await BrowserCookies.shared.snapshot(for: browser, ytdlp: tools.ytdlp, forceRefresh: true)
                if snapshot.value("sessionid", domain: "instagram.com") != nil {
                    status = "Signed in to Instagram"
                    statusIsGood = true
                } else {
                    status = "Not signed in to Instagram in \(browser.displayName)"
                    statusIsGood = false
                }
            } catch {
                status = error.friendlyMessage
                statusIsGood = false
            }
            checking = false
        }
    }
}

struct EngineSettingsView: View {
    @Environment(AppModel.self) var model
    @AppStorage(PrefKey.autoUpdateEngine) var autoUpdate = true

    var body: some View {
        Form {
            Section {
                ForEach(ToolID.allCases, id: \.self) { tool in
                    LabeledContent {
                        Text(model.toolVersions[tool] ?? "Not installed")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.displayName)
                            Text(tool.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Components")
            }
            Section {
                Toggle("Keep the download engine up to date", isOn: $autoUpdate)
                HStack(spacing: 10) {
                    Button("Check for Updates") {
                        Task { await model.updateEngine(force: true) }
                    }
                    .disabled(model.isUpdatingEngine)
                    Button("Reinstall Components") {
                        Task { await model.prepareEngine(reinstall: true) }
                    }
                    .disabled(model.isUpdatingEngine || model.downloads.runningCount > 0)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(AppPaths.tools)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show components in Finder")
                }
                if model.isUpdatingEngine {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.engineMessage ?? "Working…")
                            .foregroundStyle(.secondary)
                    }
                } else if let message = model.engineMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Sites change often. Downly quietly refreshes yt-dlp once a day so downloads keep working.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 400)
    }
}
