import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum UserAgent {
    public static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    public static let chrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
}

public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public let finalURL: URL
    public let headers: [String: String]

    public var text: String {
        String(decoding: data, as: UTF8.self)
    }

    public var json: J {
        J(data: data)
    }

    public var isSuccess: Bool {
        (200..<300).contains(status)
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public final class HTTPClient: @unchecked Sendable {
    public static let shared = HTTPClient()

    public let session: URLSession
    private let defaultHeaders: [String: String]

    public init(userAgent: String = UserAgent.safari, timeout: TimeInterval = 25, storesCookies: Bool = true) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(timeout * 4, 120)
        config.httpShouldSetCookies = storesCookies
        config.httpCookieAcceptPolicy = storesCookies ? .always : .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        defaultHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
        ]
    }

    public func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in defaultHeaders where headers.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) == nil {
            request.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownlyError.network("Unexpected response from \(url.host ?? "server").")
        }
        var headerMap: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headerMap[String(describing: key)] = String(describing: value)
        }
        return HTTPResult(data: data, status: http.statusCode, finalURL: http.url ?? url, headers: headerMap)
    }

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResult {
        try await request(url, headers: headers)
    }

    public func getOK(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResult {
        let result = try await get(url, headers: headers)
        guard result.isSuccess else { throw DownlyError.http(result.status) }
        return result
    }

    public func post(_ url: URL, headers: [String: String] = [:], body: Data) async throws -> HTTPResult {
        try await request(url, method: "POST", headers: headers, body: body)
    }

    public func finalURL(for url: URL) async -> URL {
        if let result = try? await request(url, method: "HEAD"), result.status < 400 {
            return result.finalURL
        }
        if let result = try? await request(url) {
            return result.finalURL
        }
        return url
    }

    public func cookies(for url: URL) -> [HTTPCookie] {
        session.configuration.httpCookieStorage?.cookies(for: url) ?? []
    }

    public func setCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            session.configuration.httpCookieStorage?.setCookie(cookie)
        }
    }
}

public final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public typealias Progress = @Sendable (_ received: Int64, _ expected: Int64?) -> Void

    private let destination: URL
    private let progress: Progress?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse?, Error>?
    private var task: URLSessionDownloadTask?
    private var pendingError: Error?
    private var cancelled = false

    private init(destination: URL, progress: Progress?) {
        self.destination = destination
        self.progress = progress
    }

    @discardableResult
    public static func download(
        _ url: URL,
        to destination: URL,
        headers: [String: String] = [:],
        progress: Progress? = nil
    ) async throws -> HTTPURLResponse? {
        var request = URLRequest(url: url)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let downloader = FileDownloader(destination: destination, progress: progress)
        return try await downloader.run(request)
    }

    private func run(_ request: URLRequest) async throws -> HTTPURLResponse? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 12
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPURLResponse?, Error>) in
                let task = session.downloadTask(with: request)
                lock.lock()
                self.continuation = continuation
                self.task = task
                let alreadyCancelled = cancelled
                lock.unlock()
                if alreadyCancelled {
                    task.cancel()
                }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lock.lock()
            pendingError = DownlyError.http(http.statusCode)
            lock.unlock()
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
        } catch {
            lock.lock()
            pendingError = error
            lock.unlock()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let pending = pendingError
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            continuation?.resume(throwing: error)
        } else if let pending {
            continuation?.resume(throwing: pending)
        } else {
            continuation?.resume(returning: task.response as? HTTPURLResponse)
        }
    }
}

public final class ProgressThrottle: @unchecked Sendable {
    private let interval: TimeInterval
    private var last: Date = .distantPast
    private let lock = NSLock()

    public init(interval: TimeInterval = 0.12) {
        self.interval = interval
    }

    public func shouldFire(force: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if force || now.timeIntervalSince(last) >= interval {
            last = now
            return true
        }
        return false
    }
}
