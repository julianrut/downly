import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum OutputChannel: Sendable {
    case stdout
    case stderr
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }

    public var combined: String { stdout + "\n" + stderr }
}

public final class ProcessRunner: @unchecked Sendable {
    public typealias LineHandler = @Sendable (String, OutputChannel) -> Void

    private let process = Process()
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutPartial = Data()
    private var stderrPartial = Data()
    private var cancelled = false
    private let onLine: LineHandler?
    private let stderrLimit = 512 * 1024

    private init(onLine: LineHandler?) {
        self.onLine = onLine
    }

    public static var baseEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let toolDir = AppPaths.tools.path
        let path = [toolDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        env["PATH"] = path
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUTF8"] = "1"
        env["NO_COLOR"] = "1"
        env["DENO_NO_UPDATE_CHECK"] = "1"
        env["DENO_NO_PROMPT"] = "1"
        return env
    }

    public static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        onLine: LineHandler? = nil
    ) async throws -> ProcessResult {
        let runner = ProcessRunner(onLine: onLine)
        return try await runner.execute(executable, arguments, environment: environment, currentDirectory: currentDirectory)
    }

    private func execute(_ executable: URL, _ arguments: [String], environment: [String: String], currentDirectory: URL?) async throws -> ProcessResult {
        try Task.checkCancellation()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessRunner.baseEnvironment
        env.merge(environment) { _, new in new }
        process.environment = env
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let group = DispatchGroup()
        group.enter()
        group.enter()
        group.enter()

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                self?.consume(data, channel: .stdout)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                self?.consume(data, channel: .stderr)
            }
        }
        process.terminationHandler = { _ in
            group.leave()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: DownlyError.toolFailed("Couldn’t start \(executable.lastPathComponent): \(error.localizedDescription)"))
                    return
                }
                lock.lock()
                let cancelledEarly = cancelled
                lock.unlock()
                if cancelledEarly {
                    terminateTree()
                }
                group.notify(queue: .global(qos: .userInitiated)) {
                    self.flushPartials()
                    self.lock.lock()
                    let out = String(decoding: self.stdoutData, as: UTF8.self)
                    let err = String(decoding: self.stderrData, as: UTF8.self)
                    let wasCancelled = self.cancelled
                    self.lock.unlock()
                    if wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: ProcessResult(status: self.process.terminationStatus, stdout: out, stderr: err))
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        terminateTree()
    }

    private func terminateTree() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let children = ProcessRunner.descendants(of: pid)
        for child in children.reversed() {
            kill(child, SIGTERM)
        }
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { [process] in
            if process.isRunning {
                for child in children {
                    kill(child, SIGKILL)
                }
                kill(pid, SIGKILL)
            }
        }
    }

    private static func descendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue: [pid_t] = [pid]
        var visited = Set<pid_t>()
        while let current = queue.popLast() {
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-P", String(current)]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                continue
            }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            for line in output.split(whereSeparator: \.isNewline) {
                if let child = pid_t(line.trimmingCharacters(in: .whitespaces)) {
                    result.append(child)
                    queue.append(child)
                }
            }
        }
        return result
    }

    private func consume(_ data: Data, channel: OutputChannel) {
        var lines: [String] = []
        lock.lock()
        switch channel {
        case .stdout:
            stdoutData.append(data)
            stdoutPartial.append(data)
            if onLine != nil {
                lines = ProcessRunner.extractLines(from: &stdoutPartial)
            } else {
                stdoutPartial.removeAll(keepingCapacity: true)
            }
        case .stderr:
            stderrData.append(data)
            if stderrData.count > stderrLimit {
                stderrData = stderrData.suffix(stderrLimit / 2)
            }
            stderrPartial.append(data)
            lines = ProcessRunner.extractLines(from: &stderrPartial)
            if onLine == nil {
                lines = []
            }
        }
        lock.unlock()
        if let onLine {
            for line in lines where !line.isEmpty {
                onLine(line, channel)
            }
        }
    }

    private func flushPartials() {
        var leftovers: [(String, OutputChannel)] = []
        lock.lock()
        if !stdoutPartial.isEmpty {
            leftovers.append((String(decoding: stdoutPartial, as: UTF8.self), .stdout))
            stdoutPartial.removeAll()
        }
        if !stderrPartial.isEmpty {
            leftovers.append((String(decoding: stderrPartial, as: UTF8.self), .stderr))
            stderrPartial.removeAll()
        }
        lock.unlock()
        if let onLine {
            for (line, channel) in leftovers where !line.isEmpty {
                onLine(line, channel)
            }
        }
    }

    private static func extractLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        var start = buffer.startIndex
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let byte = buffer[index]
            if byte == 0x0A || byte == 0x0D {
                if index > start {
                    lines.append(String(decoding: buffer[start..<index], as: UTF8.self))
                }
                start = buffer.index(after: index)
            }
            index = buffer.index(after: index)
        }
        if start > buffer.startIndex {
            buffer = Data(buffer[start..<buffer.endIndex])
        }
        return lines
    }
}

public extension ProcessRunner {
    static func output(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 60) async throws -> ProcessResult {
        try await withThrowingTaskGroup(of: ProcessResult?.self) { group in
            group.addTask {
                try await ProcessRunner.run(executable, arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            while let next = try await group.next() {
                if let result = next {
                    return result
                }
                throw DownlyError.toolFailed("\(executable.lastPathComponent) didn’t respond in time.")
            }
            throw DownlyError.toolFailed("\(executable.lastPathComponent) didn’t run.")
        }
    }
}
