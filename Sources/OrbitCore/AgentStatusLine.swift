import Foundation

/// Wrap the existing command while forwarding the same JSON and terminal output.
/// The exact original object is kept separately, and restored only while we own it.
public enum AgentStatusLine {
    public static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func installing(in settings: [String: Any], bridge: String, record: [String: Any]?) throws -> (settings: [String: Any], record: [String: Any]) {
        let original = settings["statusLine"]
        if let record, owns(settings, record: record) { return (settings, record) }
        if let original, !(original is [String: Any]) { throw failure("Your Claude status line has an unsupported format. It was left unchanged.") }
        let object = original as? [String: Any]
        if let object, object["type"] as? String != "command" || object["command"] as? String == nil {
            throw failure("Your Claude status line has an unsupported format. It was left unchanged.")
        }
        let capture = quote(bridge) + " --claude-metrics"
        let command: String
        if let existing = object?["command"] as? String {
            guard !existing.contains("--claude-metrics") else { throw failure("Orbit’s status-line restore record is missing. Restore your original status line before reconnecting metrics.") }
            command = "ORBIT_STATUS_INPUT=$(cat)\nprintf '%s' \"$ORBIT_STATUS_INPUT\" | " + capture + " >/dev/null 2>&1\nprintf '%s' \"$ORBIT_STATUS_INPUT\" | /bin/sh -c " + quote(existing)
        } else { command = capture }
        var statusLine = object ?? [:]; statusLine["type"] = "command"; statusLine["command"] = command
        var result = settings; result["statusLine"] = statusLine
        return (result, ["original": original ?? NSNull(), "installedCommand": command, "installed": statusLine])
    }
    public static func owns(_ settings: [String: Any], record: [String: Any]) -> Bool {
        guard let command = record["installedCommand"] as? String else { return false }
        guard (settings["statusLine"] as? [String: Any])?["command"] as? String == command,
              let installed = record["installed"] as? [String: Any], let current = settings["statusLine"] as? [String: Any] else { return false }
        return NSDictionary(dictionary: installed).isEqual(to: current)
    }
    public static func removing(from settings: [String: Any], record: [String: Any]) throws -> [String: Any] {
        guard owns(settings, record: record) else { throw failure("Your Claude status line changed after connection. Orbit left that edit untouched.") }
        var result = settings
        if record["original"] is NSNull { result.removeValue(forKey: "statusLine") }
        else if let original = record["original"] as? [String: Any] { result["statusLine"] = original }
        else { throw failure("The status-line restore record is unreadable. Settings were left unchanged.") }
        return result
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
