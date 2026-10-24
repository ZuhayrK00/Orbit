import Foundation

public enum AIProvider: String, CaseIterable, Identifiable {
    case codex, claude
    public var id: String { rawValue }
    public var title: String { self == .codex ? "Codex" : "Claude Code" }
    public var hookFlag: String { self == .codex ? "--codex-hook" : "--claude-hook" }
}

/// Only these display fields cross into Orbit. Provider credentials never do.
public struct ProviderAccount: Equatable {
    public let email: String?
    public let plan: String?
    public let method: String
    public let configurationDirectory: String?
    public var usesSubscription: Bool { method == "chatgpt" || method == "claude.ai" }
    public var displayName: String { email ?? (usesSubscription ? "Signed-in account" : "Provider credentials configured") }
    public var planLabel: String {
        switch plan?.lowercased() {
        case "prolite": return "Pro Lite"
        case "max": return "Max"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team", "business": return "Business"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return plan?.capitalized ?? (usesSubscription ? "Subscription" : "API / provider billing")
        }
    }
    public static func codex(_ response: [String: Any]) -> ProviderAccount? {
        guard let account = response["account"] as? [String: Any], let type = account["type"] as? String else { return nil }
        guard ["chatgpt", "apiKey", "amazonBedrock"].contains(type) else { return nil }
        return ProviderAccount(email: clean(account["email"]), plan: clean(account["planType"]), method: type, configurationDirectory: nil)
    }
    public static func claude(_ response: [String: Any]) -> ProviderAccount? {
        guard response["loggedIn"] as? Bool == true, let method = response["authMethod"] as? String, method != "none" else { return nil }
        return ProviderAccount(email: clean(response["email"]), plan: clean(response["subscriptionType"]), method: method, configurationDirectory: clean(response["configDirectory"], limit: 4096))
    }
    private static func clean(_ value: Any?, limit: Int = 254) -> String? {
        guard let value = value as? String else { return nil }
        let clean = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(limit))
    }
}

public enum ProviderLoginURL {
    public static func allowed(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), ["auth.openai.com", "auth0.openai.com", "chatgpt.com", "login.openai.com"].contains(host),
              url.port == nil || url.port == 443 else { return nil }
        return url
    }
}
