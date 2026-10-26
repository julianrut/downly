import Foundation

public enum DownlyError: LocalizedError, Equatable, Sendable {
    case unsupportedLink
    case needsLogin(Platform, String)
    case botCheck
    case unavailable(String)
    case network(String)
    case http(Int)
    case toolMissing(String)
    case toolFailed(String)
    case noMatch(String)
    case nothingToDownload
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            return "This link isn’t supported."
        case .needsLogin(let platform, let detail):
            return detail.isEmpty ? "\(platform.displayName) needs you to be signed in for this." : detail
        case .botCheck:
            return "YouTube asked to confirm you’re not a bot."
        case .unavailable(let detail):
            return detail
        case .network(let detail):
            return detail
        case .http(let code):
            return "The server responded with an error (\(code))."
        case .toolMissing(let name):
            return "\(name) isn’t installed yet."
        case .toolFailed(let detail):
            return detail
        case .noMatch(let detail):
            return detail
        case .nothingToDownload:
            return "There’s nothing downloadable at this link."
        case .message(let text):
            return text
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .needsLogin(let platform, _):
            return "Open Settings → Accounts, pick the browser where you’re signed in to \(platform.displayName), then try again."
        case .botCheck:
            return "Open Settings → Accounts and pick the browser you use YouTube in. Downly will use that session."
        case .network:
            return "Check your internet connection and try again."
        case .toolMissing, .toolFailed:
            return "Open Settings → Engine and choose “Reinstall components”."
        default:
            return nil
        }
    }

    public var needsAccount: Bool {
        switch self {
        case .needsLogin, .botCheck: return true
        default: return false
        }
    }
}

extension Error {
    public var isCancellation: Bool {
        if self is CancellationError { return true }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    public var friendlyMessage: String {
        if let error = self as? DownlyError {
            return error.errorDescription ?? "Something went wrong."
        }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "You’re offline."
            case NSURLErrorTimedOut: return "The connection timed out."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "Couldn’t reach the server."
            default: return ns.localizedDescription
            }
        }
        return localizedDescription
    }
}
