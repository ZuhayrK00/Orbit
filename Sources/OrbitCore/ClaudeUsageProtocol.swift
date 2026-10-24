import Foundation

public enum ClaudeUsageProtocol {
    public static func supported(version: String) -> Bool {
        let number = version.split(whereSeparator: { !$0.isNumber && $0 != "." }).first ?? ""
        let parts = number.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return false }
        return !parts.prefix(3).lexicographicallyPrecedes([2, 1, 286])
    }
    public static func windows(_ result: [String: Any], now: Date = Date()) -> [AgentLimitWindow] {
        guard result["rate_limits_available"] as? Bool == true, let rates = result["rate_limits"] as? [String: Any] else { return [] }
        let date = ISO8601DateFormatter(), fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [("five_hour", "Claude · 5h"), ("seven_day", "Claude · 7d"), ("seven_day_opus", "Claude Opus · 7d"), ("seven_day_sonnet", "Claude Sonnet · 7d")].compactMap { key, title in
            guard let window = rates[key] as? [String: Any], let percent = AgentUsage.number(window["utilization"]), (0...100).contains(percent),
                  let raw = window["resets_at"] as? String, let reset = fractional.date(from: raw) ?? date.date(from: raw), reset > now else { return nil }
            return AgentLimitWindow(id: "claude." + key, label: title, usedPercent: percent, resetsAt: reset)
        }
    }
}
