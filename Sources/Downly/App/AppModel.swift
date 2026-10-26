import AppKit
import DownlyCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum SetupState: Equatable {
        case checking
        case installing
        case ready
        case failed(String)
    }

    enum AnalysisState {
        case idle
        case loading(ParsedLink, MediaSummary?)
        case loaded(ParsedLink, Analysis)
        case failed(ParsedLink?, String, String?, Bool)
    }

    var setup: SetupState = .checking
    var toolPhases: [ToolID: ToolInstallPhase] = [:]
    var toolVersions: [ToolID: String] = [:]
    var engineMessage: String?
    var isUpdatingEngine = false

    var input: String = ""
    var analysis: AnalysisState = .idle
    var analysisID = UUID()
    var clipboardSuggestion: ParsedLink?
    var focusRequest = UUID()
    var showSettingsTab: String?

    let downloads = DownloadManager()

    @ObservationIgnored private(set) var tools: ToolPaths?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var lastClipboardChange = -1
    @ObservationIgnored private var dismissedClipboard: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var updatesScheduled = false

    init() {
        Preferences.register()
        downloads.contextProvider = { [weak self] in
            guard let tools = self?.tools else { return nil }
            return DownloadContext(
                tools: tools,
                settings: Preferences.engineSettings,
                destination: Preferences.downloadFolder,
                embedMetadata: Preferences.embedMetadata,
                filenameStyle: Preferences.filenameStyle
            )
        }
    }

    func start() {
        guard !started else { return }
        started = true
        downloads.restore()
        AppPaths.cleanStaging()
        Task {
            await prepareEngine()
        }
    }

    func prepareEngine(reinstall: Bool = false) async {
        let toolchain = Toolchain.shared
        if !reinstall, let paths = await toolchain.paths() {
            tools = paths
            toolVersions = await toolchain.versions()
            setup = .ready
            checkClipboard()
            scheduleEngineUpdates()
            return
        }
        setup = reinstall && tools != nil ? .ready : .installing
        if reinstall {
            isUpdatingEngine = true
            engineMessage = "Reinstalling components…"
        }
        let missing = await toolchain.missingTools()
        let pending = reinstall ? ToolID.allCases : missing
        toolPhases = Dictionary(uniqueKeysWithValues: pending.map { ($0, ToolInstallPhase.waiting) })
        do {
            let handler: @Sendable (ToolID, ToolInstallPhase) -> Void = { tool, phase in
                Task { @MainActor in
                    self.toolPhases[tool] = phase
                }
            }
            let paths: ToolPaths
            if reinstall {
                paths = try await toolchain.reinstallAll(progress: handler)
            } else {
                paths = try await toolchain.install(progress: handler)
            }
            tools = paths
            toolVersions = await toolchain.versions()
            withAnimation(.easeInOut(duration: 0.4)) {
                setup = .ready
            }
            engineMessage = reinstall ? "Components reinstalled." : nil
            checkClipboard()
            if !reinstall {
                scheduleEngineUpdates()
            }
        } catch {
            if tools == nil {
                setup = .failed(error.friendlyMessage)
            } else {
                engineMessage = error.friendlyMessage
            }
        }
        isUpdatingEngine = false
    }

    func scheduleEngineUpdates() {
        guard !updatesScheduled else { return }
        updatesScheduled = true
        Task {
            while !Task.isCancelled {
                if Preferences.autoUpdateEngine {
                    await self.updateEngine(force: false)
                }
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
    }

    func updateEngine(force: Bool) async {
        guard !isUpdatingEngine else { return }
        if !force && downloads.runningCount > 0 { return }
        isUpdatingEngine = true
        if force { engineMessage = "Checking for updates…" }
        let updated = await Toolchain.shared.updateYTDLPIfNeeded(force: force)
        if let updated {
            tools = await Toolchain.shared.paths()
            engineMessage = "Updated yt-dlp to \(updated)."
        } else if force {
            engineMessage = "Everything is up to date."
        }
        toolVersions = await Toolchain.shared.versions()
        isUpdatingEngine = false
    }

    func retrySetup() {
        setup = .checking
        Task { await prepareEngine() }
    }

    func submit(_ text: String? = nil) {
        let raw = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let link = LinkParser.firstLink(in: raw) else {
            withAnimationIfPossible {
                analysis = .failed(nil, "That doesn’t look like a link.", "Paste a link from YouTube, Spotify, Instagram, TikTok or another video site.", false)
            }
            return
        }
        input = link.url.absoluteString
        analyze(link)
    }

    func analyze(_ link: ParsedLink) {
        if case .loading(let current, _) = analysis, current.url == link.url {
            return
        }
        if case .loaded(let current, _) = analysis, current.url == link.url {
            return
        }
        analysisTask?.cancel()
        clipboardSuggestion = nil
        analysisID = UUID()
        let id = analysisID
        withAnimationIfPossible {
            analysis = .loading(link, nil)
        }
        analysisTask = Task {
            let previewTask = Task { @MainActor in
                let summary = await QuickPreview().summary(for: link)
                if let summary, self.analysisID == id, case .loading = self.analysis {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.analysis = .loading(link, summary)
                    }
                }
            }
            guard let tools = await self.waitForTools() else {
                if self.analysisID == id {
                    self.analysis = .failed(link, "Downly is still getting ready.", nil, false)
                }
                return
            }
            let analyzer = Analyzer(tools: tools, settings: Preferences.engineSettings)
            do {
                let result = try await analyzer.analyze(link)
                previewTask.cancel()
                guard self.analysisID == id, !Task.isCancelled else { return }
                withAnimationIfPossible {
                    self.analysis = .loaded(link, result)
                }
            } catch {
                previewTask.cancel()
                guard self.analysisID == id, !error.isCancellation, !Task.isCancelled else { return }
                let known = error as? DownlyError
                withAnimationIfPossible {
                    self.analysis = .failed(link, error.friendlyMessage, known?.recoverySuggestion, known?.needsAccount ?? false)
                }
            }
        }
    }

    func analyzePlaylist(url: String, platform: Platform) {
        guard let parsed = URL(string: url) else { return }
        analyze(ParsedLink(url: parsed, platform: platform, kind: .youtubePlaylist(id: ""), playlistID: nil))
    }

    func retryAnalysis() {
        switch analysis {
        case .failed(let link?, _, _, _):
            analyze(link)
        default:
            submit()
        }
    }

    private func waitForTools() async -> ToolPaths? {
        for _ in 0..<600 {
            if let tools { return tools }
            if case .failed = setup { return nil }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return nil }
        }
        return tools
    }

    func clear() {
        analysisTask?.cancel()
        input = ""
        analysisID = UUID()
        withAnimationIfPossible {
            analysis = .idle
        }
        focusRequest = UUID()
    }

    func enqueue(_ jobs: [DownloadJob]) {
        guard !jobs.isEmpty else { return }
        downloads.add(jobs)
        analysisTask?.cancel()
        input = ""
        analysisID = UUID()
        withAnimationIfPossible {
            analysis = .idle
        }
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        input = text
        submit(text)
    }

    func checkClipboard() {
        guard Preferences.watchClipboard, setup == .ready else { return }
        let board = NSPasteboard.general
        guard board.changeCount != lastClipboardChange else { return }
        lastClipboardChange = board.changeCount
        guard let text = board.string(forType: .string), text.count < 2000 else {
            clipboardSuggestion = nil
            return
        }
        guard let link = LinkParser.firstLink(in: text), link.platform != .web else {
            clipboardSuggestion = nil
            return
        }
        if link.url.absoluteString == dismissedClipboard { return }
        if case .loaded(let current, _) = analysis, current.url == link.url { return }
        if case .loading(let current, _) = analysis, current.url == link.url { return }
        if downloads.items.prefix(5).contains(where: { $0.job.subtitle == link.url.absoluteString }) { return }
        withAnimationIfPossible {
            clipboardSuggestion = link
        }
    }

    func useClipboardSuggestion() {
        guard let link = clipboardSuggestion else { return }
        input = link.url.absoluteString
        analyze(link)
    }

    func dismissClipboardSuggestion() {
        dismissedClipboard = clipboardSuggestion?.url.absoluteString
        withAnimationIfPossible {
            clipboardSuggestion = nil
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        self.input = url.absoluteString
                        self.submit(url.absoluteString)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        self.input = text
                        self.submit(text)
                    }
                }
                return true
            }
        }
        return false
    }
}
