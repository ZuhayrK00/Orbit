import AppKit
import SwiftUI
import OrbitCore

/// Shared identity for account cards, sessions and live activities. Read the
/// installed provider's artwork once; no logos are downloaded or redistributed.
struct AgentProviderIcon: View {
    let provider: AIProvider?
    var size: CGFloat = 16
    var tint: Color? = nil

    var body: some View {
        Group {
            if let provider {
                switch AgentProviderArtwork.image(for: provider) {
                case .template(let image):
                    Image(nsImage: image).resizable().renderingMode(.template)
                        .interpolation(.high).scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundStyle(tint ?? provider.iconColor)
                case .application(let image):
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: size, height: size)
                case .unavailable:
                    Image(systemName: provider.iconSymbol).font(.system(size: size * 0.85, weight: .semibold))
                        .foregroundStyle(tint ?? provider.iconColor)
                }
            } else {
                Image(systemName: "sparkles").font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(tint ?? .secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true).allowsHitTesting(false)
    }
}

extension AIProvider {
    init?(activityName: String) {
        switch activityName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex": self = .codex
        case "claude", "claude code": self = .claude
        default: return nil
        }
    }
    var iconSymbol: String { self == .codex ? "chevron.left.forwardslash.chevron.right" : "sparkle" }
    var iconColor: Color { self == .codex ? .white.opacity(0.9) : Color(red: 0.87, green: 0.56, blue: 0.43) }
}

private enum AgentProviderArtwork {
    enum Artwork { case template(NSImage), application(NSImage), unavailable }
    private static var cache: [AIProvider: Artwork] = [:]

    static func image(for provider: AIProvider) -> Artwork {
        if let cached = cache[provider] { return cached }
        let identifiers = provider == .codex ? ["com.openai.codex", "com.openai.chatgpt"] : ["com.anthropic.claudefordesktop"]
        let resource = provider == .codex ? "chatgptTemplate" : "TrayIconTemplate"
        var fallback: NSImage?
        for identifier in identifiers {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            if let image = Bundle(url: app)?.image(forResource: resource)?.copy() as? NSImage {
                image.isTemplate = true
                let artwork = Artwork.template(image)
                cache[provider] = artwork
                return artwork
            }
            if fallback == nil { fallback = NSWorkspace.shared.icon(forFile: app.path) }
        }
        let artwork = fallback.map(Artwork.application) ?? .unavailable
        cache[provider] = artwork
        return artwork
    }
}
