import Foundation

public enum OrbitPermission: String, CaseIterable, Sendable, Identifiable {
    case accessibility, screenCapture, calendar, notifications, inputMonitoring
    case music, spotify, finder, systemAudio, files
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenCapture: return "Screen recording"
        case .calendar: return "Calendar"
        case .notifications: return "Orbit alerts"
        case .inputMonitoring: return "Input monitoring"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        case .finder: return "Finder"
        case .systemAudio: return "System audio"
        case .files: return "Files & folders"
        }
    }
    public var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenCapture: return "viewfinder"
        case .calendar: return "calendar"
        case .notifications: return "bell.badge"
        case .inputMonitoring: return "computermouse"
        case .music, .spotify: return "music.note"
        case .finder: return "macwindow"
        case .systemAudio: return "waveform"
        case .files: return "folder"
        }
    }
    public var detail: String {
        switch self {
        case .accessibility: return "Mouse gestures, selected text, notification mirroring and pointer movement."
        case .screenCapture: return "Read text from a screen area you select. Recognition stays on this Mac."
        case .calendar: return "Your agenda, meeting countdowns and Join buttons. Orbit reads events; it does not edit them."
        case .notifications: return "Timer and focus alerts from Orbit. Mirroring other apps’ notifications uses Accessibility instead."
        case .inputMonitoring: return "Additional troubleshooting for mouse buttons if Accessibility is enabled but the mouse is not connected."
        case .music, .spotify: return "Automation access for Now Playing, artwork and playback controls."
        case .finder: return "Automation access to use selected Finder files in Orbit’s file tools."
        case .systemAudio: return "Per-app volume control. macOS requests access when a mixer route is first created."
        case .files: return "Files you choose, your file shelf and the download folder you enable. Access is granted per location."
        }
    }
    public var automationBundleID: String? {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .finder: return "com.apple.finder"
        default: return nil
        }
    }
    public var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenCapture: pane = "Privacy_ScreenCapture"
        case .calendar: pane = "Privacy_Calendars"
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .music, .spotify, .finder: pane = "Privacy_Automation"
        case .systemAudio: pane = "Privacy_AudioCapture"
        case .files: pane = "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane)!
    }
    public var resetService: String? {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenCapture: return "ScreenCapture"
        default: return nil
        }
    }
    public func canRequest(_ status: PermissionStatus) -> Bool {
        guard ![.granted, .denied, .restricted, .unavailable, .checking].contains(status) else { return false }
        switch self {
        case .accessibility, .screenCapture, .inputMonitoring: return status == .notGranted
        case .calendar: return status == .notRequested || status == .limited
        case .notifications: return status == .notRequested
        case .music, .spotify, .finder: return status == .notRequested
        case .systemAudio, .files: return false
        }
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case checking, granted, notGranted, notRequested, denied, restricted, limited, unknown, unavailable
    public var title: String {
        switch self {
        case .checking: return "Checking…"
        case .granted: return "Allowed"
        case .notGranted: return "Not enabled"
        case .notRequested: return "Not requested"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        case .limited: return "Limited"
        case .unknown: return "Checked when used"
        case .unavailable: return "Unavailable"
        }
    }
}
