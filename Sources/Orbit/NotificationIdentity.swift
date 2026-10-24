import AppKit
import SwiftUI
import OrbitCore

@MainActor enum NotificationIdentity {
    private static var cache: [String: (String, String)] = [:]
    private static var icons: [String: NSImage] = [:]
    static func resolve(_ notice: NotchNotice) -> NotchNotice {
        var notice = notice
        guard notice.bundleID == nil else { return notice }
        let name = notice.app.replacingOccurrences(of: " application icon", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " icon", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return notice }
        if let cached = cache[name] { notice.app = cached.0; notice.bundleID = cached.1; return notice }
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }), let id = app.bundleIdentifier {
            notice.app = app.localizedName ?? name; notice.bundleID = id; cache[name] = (notice.app, id)
        } else {
            let known = ["WhatsApp": "net.whatsapp.WhatsApp", "Microsoft Teams": "com.microsoft.teams2", "Teams": "com.microsoft.teams2", "Messages": "com.apple.MobileSMS", "Mail": "com.apple.mail", "Safari": "com.apple.Safari", "Calendar": "com.apple.iCal", "Phone": "com.apple.mobilephone", "FaceTime": "com.apple.FaceTime", "Orbit": Bundle.main.bundleIdentifier ?? ""]
            if let entry = known.first(where: { $0.key.localizedCaseInsensitiveCompare(name) == .orderedSame }), NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.value) != nil {
                notice.app = entry.key; notice.bundleID = entry.value; cache[name] = (notice.app, entry.value)
            }
        }
        return notice
    }
    static func icon(_ notice: NotchNotice) -> NSImage? {
        let id = notice.isSample ? Bundle.main.bundleIdentifier : notice.bundleID
        guard let id else { return nil }
        if let icon = icons[id] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path); icons[id] = icon; return icon
    }
}

struct NotificationAppIcon: View {
    let notice: NotchNotice
    var size: CGFloat = 34
    var body: some View {
        Group {
            if let image = NotificationIdentity.icon(notice) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: notice.isCall ? "phone.fill" : "bell.badge.fill").resizable().scaledToFit().padding(size * 0.17).foregroundStyle(.white.opacity(0.85)) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
