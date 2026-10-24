import Foundation
import CoreFoundation

public struct AgentLimitWindow: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var remainingPercent: Double { max(0, 100 - usedPercent) }
    public var isValid: Bool { usedPercent.isFinite && (0...100).contains(usedPercent) && label.count <= 128 && id.count <= 256 }
}

public enum AgentUsage {
    public static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    public static func clean(_ value: Any?, limit: Int = 128) -> String? {
        guard let value = value as? String else { return nil }
        let text = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(limit))
    }
    private static func window(_ json: [String: Any]?, id: String, label: String, percent: String, reset: String) -> AgentLimitWindow? {
        guard let json, let used = number(json[percent]), used >= 0 else { return nil }
        let date = number(json[reset]).flatMap { $0 > 0 && $0 < 253402300800 ? Date(timeIntervalSince1970: $0) : nil }
        return AgentLimitWindow(id: id, label: label, usedPercent: min(100, used), resetsAt: date)
    }
    public static func codexLimits(_ response: [String: Any]) -> [AgentLimitWindow] {
        let buckets: [String: Any]
        if let multiple = response["rateLimitsByLimitId"] as? [String: Any] { buckets = multiple }
        else if let single = response["rateLimits"] as? [String: Any] { buckets = [single["limitId"] as? String ?? "codex": single] }
        else { return [] }
        return buckets.keys.sorted().prefix(16).flatMap { key -> [AgentLimitWindow] in
            guard let bucket = buckets[key] as? [String: Any] else { return [] }
            let name = clean(bucket["limitName"]) ?? (key == "codex" ? "Codex" : String(key.prefix(80)))
            return ["primary", "secondary"].compactMap { kind in
                let data = bucket[kind] as? [String: Any]
                let minutes = number(data?["windowDurationMins"])
                let period: String
                if let minutes, minutes > 0, minutes <= 525600 {
                    if minutes.truncatingRemainder(dividingBy: 1440) == 0 { period = "\(Int(minutes / 1440))d" }
                    else if minutes.truncatingRemainder(dividingBy: 60) == 0 { period = "\(Int(minutes / 60))h" }
                    else { period = "\(Int(minutes))m" }
                } else { period = kind == "primary" ? "Current window" : "Longer window" }
                return window(data, id: String(key.prefix(200)) + "." + kind, label: "\(name) · \(period)", percent: "usedPercent", reset: "resetsAt")
            }
        }
    }
    public static func claudeLimits(_ json: [String: Any]) -> [AgentLimitWindow] {
        let limits = json["rate_limits"] as? [String: Any] ?? [:]
        return [("five_hour", "Claude · 5h"), ("seven_day", "Claude · 7d")].compactMap { key, label in
            window(limits[key] as? [String: Any], id: key, label: label, percent: "used_percentage", reset: "resets_at")
        }
    }
}

/// Only documented display metadata is retained, never the transcript or prompt.
public struct AgentSessionMetrics: Codable, Equatable, Identifiable {
    public var id: String
    public var provider: String
    public var project: String
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var contextUsedPercent: Double?
    public var estimatedAPIValueUSD: Double?
    public var limits: [AgentLimitWindow]
    public var updatedAt: Date
    public static func claude(_ json: [String: Any], now: Date = Date()) -> AgentSessionMetrics? {
        guard let session = AgentUsage.clean(json["session_id"], limit: 4096) else { return nil }
        let workspace = json["workspace"] as? [String: Any] ?? [:]
        let context = json["context_window"] as? [String: Any] ?? [:]
        func count(_ field: String) -> Int? {
            guard let number = AgentUsage.number(context[field]), number >= 0, number < 1e12 else { return nil }
            return Int(number)
        }
        let percentage = AgentUsage.number(context["used_percentage"]).flatMap { (0...100).contains($0) ? $0 : nil }
        let cost = AgentUsage.number((json["cost"] as? [String: Any])?["total_cost_usd"]).flatMap { $0 >= 0 && $0 < 1e9 ? $0 : nil }
        let folder = AgentUsage.clean(workspace["project_dir"] ?? workspace["current_dir"] ?? json["cwd"], limit: 4096)
        return AgentSessionMetrics(id: "claude-" + session, provider: "Claude", project: String(folder.map { URL(fileURLWithPath: $0).lastPathComponent }?.prefix(128) ?? "Claude Code"),
            model: AgentUsage.clean((json["model"] as? [String: Any])?["display_name"]), inputTokens: count("total_input_tokens"), outputTokens: count("total_output_tokens"),
            contextUsedPercent: percentage, estimatedAPIValueUSD: cost, limits: AgentUsage.claudeLimits(json), updatedAt: now)
    }
    public static var directory: URL { OrbitPaths.support.appendingPathComponent("agent-metrics", isDirectory: true) }
    public static func write(_ metrics: AgentSessionMetrics, directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent(AgentBridge.fileName(for: metrics.id))
        try encoder.encode(metrics).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func read(directory: URL = directory, now: Date = Date()) -> [AgentSessionMetrics] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.prefix(100).compactMap { url in
            guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), info.isSymbolicLink != true, (info.fileSize ?? 0) < 65536,
                  let data = try? Data(contentsOf: url), let item = try? decoder.decode(Self.self, from: data),
                  item.id.count <= 4103, (item.model?.count ?? 0) <= 128, item.project.count <= 128,
                  item.limits.count <= 32, item.limits.allSatisfy(\.isValid), item.updatedAt <= now.addingTimeInterval(60),
                  item.contextUsedPercent.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
                  item.estimatedAPIValueUSD.map({ $0.isFinite && $0 >= 0 && $0 < 1e9 }) ?? true,
                  item.inputTokens.map({ (0..<1_000_000_000_000).contains($0) }) ?? true,
                  item.outputTokens.map({ (0..<1_000_000_000_000).contains($0) }) ?? true else { return nil }
            return item
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
