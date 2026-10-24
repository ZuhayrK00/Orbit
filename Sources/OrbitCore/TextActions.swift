import Foundation

public enum TextTransform: String, CaseIterable, Identifiable {
    case unchanged, uppercase, lowercase, titleCase, trim, singleLine, uniqueLines, sortLines, cleanLink, encodeURL, decodeURL, formatJSON
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .unchanged: return "Original"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .trim: return "Trim spaces"
        case .singleLine: return "One line"
        case .uniqueLines: return "Unique lines"
        case .sortLines: return "Sort lines"
        case .cleanLink: return "Clean link"
        case .encodeURL: return "URL encode"
        case .decodeURL: return "URL decode"
        case .formatJSON: return "Format JSON"
        }
    }
    public var symbol: String {
        switch self {
        case .unchanged: return "text.alignleft"
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .titleCase: return "textformat"
        case .trim: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .singleLine: return "line.3.horizontal.decrease"
        case .uniqueLines: return "line.3.horizontal.decrease.circle"
        case .sortLines: return "arrow.up.arrow.down"
        case .cleanLink: return "link"
        case .encodeURL: return "curlybraces"
        case .decodeURL: return "curlybraces.square"
        case .formatJSON: return "curlybraces.square.fill"
        }
    }
    public func apply(to text: String) throws -> String {
        guard text.utf8.count <= TextActions.maximumBytes else { throw TextActionError("Use text under 128 KB.") }
        switch self {
        case .unchanged: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase: return text.capitalized
        case .trim: return TextActions.lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .newlines)
        case .singleLine: return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        case .uniqueLines:
            var seen = Set<String>()
            return TextActions.lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .sortLines: return TextActions.lines(text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .cleanLink: return try TextActions.cleanLink(text)
        case .encodeURL: return text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? text
        case .decodeURL:
            guard let decoded = text.removingPercentEncoding else { throw TextActionError("This text contains an invalid URL escape.") }; return decoded
        case .formatJSON:
            guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                  let result = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
                  let string = String(data: result, encoding: .utf8) else { throw TextActionError("This text isn’t valid JSON.") }
            return string
        }
    }
}
public struct TextActionError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
public enum TextActions {
    public static let maximumBytes = 131_072
    public static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: trimmed), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
    public static func cleanLink(_ text: String) throws -> String {
        guard let url = webURL(text), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw TextActionError("Select a complete http or https link.") }
        let items = parts.percentEncodedQuery?.components(separatedBy: "&") ?? []
        func name(_ item: String) -> String { String(item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding?.lowercased() ?? "" }
        let signatures: Set<String> = ["signature", "sig", "x-amz-signature", "x-goog-signature", "oauth_signature"]
        guard !items.contains(where: { signatures.contains(name($0)) }) else { throw TextActionError("This link is signed. Keep the original so it continues to work.") }
        let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "_ga"]
        let kept = items.filter { !name($0).hasPrefix("utm_") && !tracking.contains(name($0)) }
        // Preserve the spelling, ordering and escaping of all other query fields.
        parts.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        guard let result = parts.string else { throw TextActionError("This link couldn’t be cleaned.") }; return result
    }
    public static func searchURL(_ text: String) -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 4000 else { return nil }
        var parts = URLComponents(string: "https://duckduckgo.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        return parts.url
    }
    static func lines(_ text: String) -> [String] { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") }
    public static func wordCount(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}
