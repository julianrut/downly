import AppKit
import DownlyCore
import Foundation
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case queued
        case running
        case finished
        case failed(String)
        case cancelled
    }

    let id: UUID
    let job: DownloadJob
    var state: State = .queued
    var phase: JobPhase?
    var fraction: Double?
    var speed: Double?
    var eta: Double?
    var downloaded: Int64?
    var total: Int64?
    var note: String?
    var files: [URL] = []
    var revealTarget: URL?
    var finishedAt: Date?
    var failureHint: String?

    @ObservationIgnored var task: Task<Void, Never>?

    init(job: DownloadJob) {
        self.id = job.id
        self.job = job
    }

    var isActive: Bool {
        state == .queued || state == .running
    }

    var isFinished: Bool {
        state == .finished
    }

    var fileSize: Int64? {
        let sizes = files.compactMap { url -> Int64? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
            return Int64(size)
        }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    var filesExist: Bool {
        files.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}

struct DownloadRecord: Codable {
    var job: DownloadJob
    var files: [String]
    var reveal: String?
    var finishedAt: Date
    var note: String?
}

@MainActor
@Observable
final class DownloadManager {
    var items: [DownloadItem] = []

    @ObservationIgnored var contextProvider: (() -> DownloadContext?)?
    @ObservationIgnored private var notificationsAuthorized: Bool?

    var activeCount: Int {
        items.filter(\.isActive).count
    }

    var runningCount: Int {
        items.filter { $0.state == .running }.count
    }

    var hasFinished: Bool {
        items.contains { !$0.isActive }
    }

    var overallFraction: Double? {
        let active = items.filter { $0.state == .running }
        guard !active.isEmpty else { return nil }
        let total = active.reduce(0.0) { $0 + ($1.fraction ?? 0) }
        return total / Double(active.count)
    }

    func add(_ jobs: [DownloadJob]) {
        let newItems = jobs.map(DownloadItem.init(job:))
        withAnimationIfPossible {
            items.insert(contentsOf: newItems, at: 0)
        }
        pump()
    }

    func pump() {
        let limit = Preferences.maxConcurrent
        var running = runningCount
        for item in items.reversed() where item.state == .queued {
            guard running < limit else { break }
            start(item)
            running += 1
        }
        updateDockBadge()
    }

    private func start(_ item: DownloadItem) {
        guard let context = contextProvider?() else {
            item.state = .failed("Downly is still getting ready. Try again in a moment.")
            return
        }
        item.state = .running
        item.phase = .preparing("Starting")
        item.fraction = nil
        item.note = nil
        let job = item.job
        let engine = DownloadEngine(context: context)
        item.task = Task {
            do {
                let output = try await engine.run(job) { progress in
                    Task { @MainActor in
                        self.apply(progress, to: item)
                    }
                }
                self.complete(item, output: output)
            } catch {
                self.fail(item, error: error)
            }
        }
    }

    private func apply(_ progress: JobProgress, to item: DownloadItem) {
        guard item.state == .running else { return }
        item.phase = progress.phase
        if let fraction = progress.fraction {
            item.fraction = fraction
        } else if case .downloading = progress.phase {
        } else {
            item.fraction = nil
        }
        item.speed = progress.speed
        item.eta = progress.eta
        if let downloaded = progress.downloadedBytes { item.downloaded = downloaded }
        if let total = progress.totalBytes { item.total = total }
        if let note = progress.note { item.note = note }
    }

    private func complete(_ item: DownloadItem, output: JobOutput) {
        guard item.state == .running else { return }
        item.files = output.files
        item.revealTarget = output.revealTarget
        item.note = output.note ?? item.note
        item.fraction = 1
        item.finishedAt = Date()
        item.task = nil
        withAnimationIfPossible {
            item.state = .finished
        }
        didFinish(item)
    }

    private func fail(_ item: DownloadItem, error: Error) {
        item.task = nil
        if error.isCancellation || item.state == .cancelled {
            item.state = .cancelled
        } else {
            item.state = .failed(error.friendlyMessage)
            item.failureHint = (error as? DownlyError)?.recoverySuggestion
        }
        pump()
        persist()
    }

    private func didFinish(_ item: DownloadItem) {
        pump()
        persist()
        notify(item)
    }

    func cancel(_ item: DownloadItem) {
        item.state = .cancelled
        item.task?.cancel()
        item.task = nil
        pump()
    }

    func retry(_ item: DownloadItem) {
        guard !item.isActive else { return }
        item.state = .queued
        item.fraction = nil
        item.files = []
        item.failureHint = nil
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            items.insert(item, at: 0)
        }
        pump()
    }

    func remove(_ item: DownloadItem) {
        if item.isActive {
            cancel(item)
        }
        withAnimationIfPossible {
            items.removeAll { $0.id == item.id }
        }
        persist()
    }

    func clearFinished() {
        withAnimationIfPossible {
            items.removeAll { !$0.isActive }
        }
        persist()
    }

    func cancelAll() {
        for item in items where item.isActive {
            cancel(item)
        }
    }

    func reveal(_ item: DownloadItem) {
        let targets = item.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if let target = item.revealTarget, FileManager.default.fileExists(atPath: target.path), targets.count > 1 {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else if !targets.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(targets)
        }
    }

    func open(_ item: DownloadItem) {
        if item.files.count > 1, let target = item.revealTarget, FileManager.default.fileExists(atPath: target.path) {
            NSWorkspace.shared.open(target)
        } else if let file = item.files.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(file)
        }
    }

    private func updateDockBadge() {
        let count = activeCount
        NSApp?.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    private func notify(_ item: DownloadItem) {
        updateDockBadge()
        guard Preferences.notifications, NSApp?.isActive == false else { return }
        let center = UNUserNotificationCenter.current()
        let title = item.job.title
        let body = item.job.detail
        Task {
            let granted: Bool
            if let known = self.notificationsAuthorized {
                granted = known
            } else {
                granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                self.notificationsAuthorized = granted
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Downloaded"
            content.subtitle = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    func persist() {
        let records = items.filter { $0.state == .finished }.prefix(200).map { item in
            DownloadRecord(job: item.job, files: item.files.map(\.path), reveal: item.revealTarget?.path, finishedAt: item.finishedAt ?? Date(), note: item.note)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Array(records)) {
            try? data.write(to: AppPaths.history, options: .atomic)
        }
        updateDockBadge()
    }

    func restore() {
        guard let data = try? Data(contentsOf: AppPaths.history) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([DownloadRecord].self, from: data) else { return }
        items = records.map { record in
            let item = DownloadItem(job: record.job)
            item.state = .finished
            item.files = record.files.map { URL(fileURLWithPath: $0) }
            item.revealTarget = record.reveal.map { URL(fileURLWithPath: $0) }
            item.finishedAt = record.finishedAt
            item.note = record.note
            item.fraction = 1
            return item
        }
    }
}

@MainActor
func withAnimationIfPossible(_ body: () -> Void) {
    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
        body()
    }
}
