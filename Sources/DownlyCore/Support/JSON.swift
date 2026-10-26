import Foundation

public struct J {
    public let raw: Any?

    public init(_ raw: Any?) {
        self.raw = raw
    }

    public init(data: Data) {
        self.raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public init(string: String) {
        self.init(data: Data(string.utf8))
    }

    public subscript(key: String) -> J {
        J((raw as? [String: Any])?[key])
    }

    public subscript(index: Int) -> J {
        guard let array = raw as? [Any], index >= 0, index < array.count else { return J(nil) }
        return J(array[index])
    }

    public subscript(path: [Any]) -> J {
        var current = self
        for component in path {
            if let key = component as? String {
                current = current[key]
            } else if let index = component as? Int {
                current = current[index]
            }
        }
        return current
    }

    public var exists: Bool {
        guard let raw else { return false }
        return !(raw is NSNull)
    }

    public var string: String? {
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber, !isBoolean(value) { return value.stringValue }
        return nil
    }

    public var nonEmptyString: String? {
        guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    public var double: Double? {
        if let value = raw as? NSNumber, !isBoolean(value) { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    public var int: Int? {
        if let value = raw as? NSNumber, !isBoolean(value) { return value.intValue }
        if let value = raw as? String { return Int(value) ?? Double(value).map { Int($0) } }
        return nil
    }

    public var int64: Int64? {
        if let value = raw as? NSNumber, !isBoolean(value) { return value.int64Value }
        if let value = raw as? String { return Int64(value) ?? Double(value).map { Int64($0) } }
        return nil
    }

    public var bool: Bool? {
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return nil
    }

    public var url: URL? {
        guard let value = nonEmptyString else { return nil }
        if value.hasPrefix("//") { return URL(string: "https:" + value) }
        return URL(string: value)
    }

    public var array: [J] {
        (raw as? [Any])?.map { J($0) } ?? []
    }

    public var dictionary: [String: J] {
        guard let object = raw as? [String: Any] else { return [:] }
        return object.mapValues { J($0) }
    }

    public var keys: [String] {
        (raw as? [String: Any]).map { Array($0.keys) } ?? []
    }

    public func firstValue(forKey key: String, maxDepth: Int = 40) -> J? {
        findAll(key: key, limit: 1, maxDepth: maxDepth).first
    }

    public func findAll(key: String, limit: Int = .max, maxDepth: Int = 40) -> [J] {
        var results: [J] = []
        func walk(_ node: Any?, depth: Int) {
            guard results.count < limit, depth <= maxDepth else { return }
            if let object = node as? [String: Any] {
                if let value = object[key] {
                    results.append(J(value))
                    if results.count >= limit { return }
                }
                for (_, value) in object {
                    walk(value, depth: depth + 1)
                    if results.count >= limit { return }
                }
            } else if let array = node as? [Any] {
                for value in array {
                    walk(value, depth: depth + 1)
                    if results.count >= limit { return }
                }
            }
        }
        walk(raw, depth: 0)
        return results
    }

    public func findObjects(limit: Int = .max, maxDepth: Int = 40, where predicate: ([String: Any]) -> Bool) -> [J] {
        var results: [J] = []
        func walk(_ node: Any?, depth: Int) {
            guard results.count < limit, depth <= maxDepth else { return }
            if let object = node as? [String: Any] {
                if predicate(object) {
                    results.append(J(object))
                    if results.count >= limit { return }
                }
                for (_, value) in object {
                    walk(value, depth: depth + 1)
                    if results.count >= limit { return }
                }
            } else if let array = node as? [Any] {
                for value in array {
                    walk(value, depth: depth + 1)
                    if results.count >= limit { return }
                }
            }
        }
        walk(raw, depth: 0)
        return results
    }

    private func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

public enum TextScan {
    public static func groups(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var output: [String] = []
        for index in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: index), in: text) {
                output.append(String(text[r]))
            } else {
                output.append("")
            }
        }
        return output
    }

    public static func first(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let groups = groups(pattern, in: text, options: options), groups.count > group else { return nil }
        let value = groups[group]
        return value.isEmpty ? nil : value
    }

    public static func all(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > group, let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    public static func scriptContents(in html: String, matchingAttributes attributePattern: String) -> [String] {
        let pattern = "<script[^>]*\(attributePattern)[^>]*>([\\s\\S]*?)</script>"
        return all(pattern, in: html, group: 1, options: [.caseInsensitive])
    }

    public static func metaContent(_ property: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]*(?:property|name)=[\"']\(escaped)[\"']",
        ]
        for pattern in patterns {
            if let value = first(pattern, in: html, options: [.caseInsensitive]) {
                return decodeHTMLEntities(value)
            }
        }
        return nil
    }

    public static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named: [String: String] = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#x27;": "'", "&#x2F;": "/",
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        for code in all("&#(\\d+);", in: result) {
            if let value = UInt32(code), let scalar = Unicode.Scalar(value) {
                result = result.replacingOccurrences(of: "&#\(code);", with: String(Character(scalar)))
            }
        }
        for code in all("&#x([0-9a-fA-F]+);", in: result) {
            if let value = UInt32(code, radix: 16), let scalar = Unicode.Scalar(value) {
                result = result.replacingOccurrences(of: "&#x\(code);", with: String(Character(scalar)))
            }
        }
        return result
    }
}
