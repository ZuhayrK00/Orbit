import Foundation

/// Edit only the exact Orbit command. Unrelated handlers and settings survive.
public enum AgentHooks {
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd", "SubagentStart", "SubagentStop"]
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "PostCompact", "Stop", "Interrupt", "SessionEnd", "SubagentStart", "SubagentStop"]
    public static func events(_ provider: AIProvider) -> [String] { provider == .codex ? codexEvents : claudeEvents }
    public static func addingClaude(to settings: [String: Any], command: String) throws -> [String: Any] {
        try setting(in: settings, provider: .claude, command: command, enabled: true)
    }
    public static func setting(in settings: [String: Any], provider: AIProvider, command: String, enabled: Bool) throws -> [String: Any] {
        func invalid() -> NSError { NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Existing \(provider.title) hooks have an unexpected format. They were left untouched."]) }
        if let existing = settings["hooks"], !(existing is [String: Any]) { throw invalid() }
        var result = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events(provider) {
            if let existing = hooks[event], !(existing is [[String: Any]]) { throw invalid() }
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries = try entries.compactMap { entry in
                guard let existing = entry["hooks"] as? [[String: Any]] else { throw invalid() }
                var preserved = entry
                let other = existing.filter { ($0["command"] as? String) != command }
                guard !other.isEmpty else { return nil }
                preserved["hooks"] = other; return preserved
            }
            if enabled { entries.append(["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 3]]]) }
            if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
        }
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }
    public static func contains(in settings: [String: Any], provider: AIProvider, command: String) -> Bool {
        installedEvents(in: settings, provider: provider, command: command).count == events(provider).count
    }
    public static func installedEvents(in settings: [String: Any], provider: AIProvider, command: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        return events(provider).filter { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
            }
        }
    }
}
