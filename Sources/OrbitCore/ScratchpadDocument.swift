import Foundation

public enum ScratchpadDocument {
    public static let maximumBytes = 524_288
    public static func load(from url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { throw TextActionError("This note couldn’t be read. The saved file has been left untouched.") }
        return text
    }
    public static func save(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        guard data.count <= maximumBytes else { throw TextActionError("This note is too large to save. Keep it under 512 KB.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
