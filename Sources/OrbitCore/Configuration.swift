import Foundation

public enum OrbitAction: String, Codable, CaseIterable, Identifiable {
    case home, shelf, downloads, screenText, wheelProfile, files, compressImage, convertImage, zipFiles, clipboard, sound, music, timer, calendar, agents, settings, openURL, openApp, shortcut, textTools, scratchpad, keepAwake, notifications
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .shelf: return "File shelf"
        case .downloads: return "Downloads"
        case .screenText: return "Copy screen text"
        case .wheelProfile: return "Open wheel profile"
        case .notifications: return "Notifications"
        case .textTools: return "Text Studio"
        case .scratchpad: return "Scratchpad"
        case .keepAwake: return "Keep awake"
        case .files: return "File tools"
        case .compressImage: return "Compress image"
        case .convertImage: return "Convert image"
        case .zipFiles: return "Zip files"
        case .clipboard: return "Clipboard"
        case .sound: return "Sound & mixer"
        case .music: return "Now playing"
        case .timer: return "Timer"
        case .calendar: return "Calendar"
        case .agents: return "Agents"
        case .settings: return "Orbit settings"
        case .openURL: return "Open a link"
        case .openApp: return "Open an app"
        case .shortcut: return "Run a Shortcut"
        }
    }
    public var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .shelf: return "tray.full"
        case .downloads: return "arrow.down.circle"
        case .screenText: return "text.viewfinder"
        case .wheelProfile: return "circle.hexagongrid"
        case .notifications: return "bell"
        case .textTools: return "text.cursor"
        case .scratchpad: return "square.and.pencil"
        case .keepAwake: return "cup.and.saucer"
        case .files: return "doc.on.doc"
        case .compressImage: return "arrow.down.right.and.arrow.up.left"
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .zipFiles: return "doc.zipper"
        case .clipboard: return "clipboard"
        case .sound: return "slider.horizontal.3"
        case .music: return "waveform"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .agents: return "sparkles"
        case .settings: return "gearshape"
        case .openURL: return "link"
        case .openApp: return "app"
        case .shortcut: return "bolt"
        }
    }
}

public struct WheelSlot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var action: OrbitAction
    public var label: String
    public var argument: String
    public init(action: OrbitAction, label: String? = nil, argument: String = "") {
        self.id = UUID(); self.action = action; self.label = label ?? action.title; self.argument = argument
    }
}

public enum TriggerBehavior: String, Codable, CaseIterable { case hold, toggle }
public enum Accent: String, Codable, CaseIterable { case violet, mint, coral, blue }

public struct OrbitConfiguration: Codable, Equatable {
    public var mouseEnabled = true
    public var mouseButton = 3
    public var mouseHoldDelay = 0.18
    public var mouseBehavior: TriggerBehavior = .hold
    public var consumeMouseButton = true
    public var keyboardEnabled = true
    public var keyCode: UInt32 = 49
    // Carbon: command=256, shift=512, option=2048, control=4096.
    public var keyModifiers: UInt32 = 2048 | 4096
    public var keyboardBehavior: TriggerBehavior = .toggle
    public var keyboardLabel = "⌃⌥Space"
    public var contextualTextWheel: Bool? = true
    public var notchEnabled = true
    public var notchHoverEnabled = true
    public var hoverDelay = 0.35
    public var collapseDelay = 0.6
    public var notchWidth = 480.0
    public var notchHeight = 390.0
    public var notchOnlyOnBuiltIn = true
    public var notchSettings: NotchOptions?
    public var notch: NotchOptions { notchSettings ?? NotchOptions() }
    public var notificationSettings: NotchNotificationOptions?
    public var notifications: NotchNotificationOptions { notificationSettings ?? NotchNotificationOptions() }
    public var menuBarEnabled = true
    public var wheelSettings: WheelOptions?
    public var wheel: WheelOptions { wheelSettings ?? WheelOptions() }
    public var wheelDiameter = 460.0
    public var wheelOpacity = 0.96
    public var accent: Accent = .violet
    public var reducedMotion = false
    public var glassTransparency: Double?
    public var effectiveGlassTransparency: Double { glassTransparency ?? 0.68 }
    public var glassColor: NotchColor?
    // Older installs already have a notch tint. Keep it as the initial shared finish.
    public var effectiveGlassColor: NotchColor { (glassColor ?? notch.color).normalized }
    public var clipboardEnabled = false
    public var clipboardLimit = 30
    public var launchAtLogin = false
    public var mediaEnabled = false
    public var timerPresets: [TimerPreset]?
    public var mixerSettings: MixerOptions?
    public var mixer: MixerOptions { mixerSettings ?? MixerOptions() }
    public var awakeSettings: AwakeOptions?
    public var awake: AwakeOptions { awakeSettings ?? AwakeOptions() }
    public var effectiveTimerPresets: [TimerPreset] { timerPresets ?? TimerPresets.defaults }
    public var productivitySettings: ProductivityOptions?
    public var productivity: ProductivityOptions { productivitySettings ?? .init() }
    public var wheelProfiles: [WheelProfile]?
    public var slots: [WheelSlot] = [
        WheelSlot(action: .files), WheelSlot(action: .clipboard), WheelSlot(action: .sound),
        WheelSlot(action: .music), WheelSlot(action: .timer), WheelSlot(action: .calendar),
        WheelSlot(action: .agents), WheelSlot(action: .settings)
    ]
    public init() {}
    public mutating func normalize() {
        productivitySettings?.normalize()
        if wheelProfiles != nil { wheelProfiles = Array(wheelProfiles!.prefix(12)); for i in wheelProfiles!.indices { wheelProfiles![i].normalize() } }
        if let glassTransparency { self.glassTransparency = glassTransparency.isFinite ? min(0.9, max(0.15, glassTransparency)) : 0.68 }
        glassColor = glassColor?.normalized
        if mixerSettings != nil { mixerSettings?.normalize() }
        if wheelSettings != nil { wheelSettings?.normalize() }
        if awakeSettings != nil { awakeSettings?.normalize() }
        if notchSettings != nil { notchSettings?.normalize() }
        if let timerPresets { self.timerPresets = TimerPresets.normalize(timerPresets) }
        if notificationSettings != nil { notificationSettings?.normalize() }
        contextualTextWheel = contextualTextWheel ?? true
        mouseButton = min(31, max(0, mouseButton))
        mouseHoldDelay = min(1.5, max(0.05, mouseHoldDelay))
        hoverDelay = min(2, max(0.05, hoverDelay))
        collapseDelay = min(3, max(0.15, collapseDelay))
        wheelDiameter = min(680, max(340, wheelDiameter))
        wheelOpacity = min(1, max(0.65, wheelOpacity))
        notchWidth = notchWidth.isFinite ? min(600, max(360, notchWidth)) : 480
        notchHeight = min(620, max(300, notchHeight))
        clipboardLimit = min(100, max(5, clipboardLimit))
        keyModifiers &= 256 | 512 | 2048 | 4096
        if keyCode > 127 { keyCode = 49; keyboardLabel = "⌃⌥Space"; keyModifiers = 2048 | 4096 }
        if keyModifiers == 0 { keyModifiers = 2048 | 4096; keyCode = 49; keyboardLabel = "⌃⌥Space" }
        if slots.count < 4 { slots = OrbitConfiguration().slots }
        slots = Array(slots.prefix(12))
        for index in slots.indices {
            if slots[index].label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { slots[index].label = slots[index].action.title }
            slots[index].label = String(slots[index].label.prefix(36))
            slots[index].argument = String(slots[index].argument.prefix(4096))
        }
    }
}

public enum OrbitPaths {
    public static var support: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Orbit", isDirectory: true)
    }
    public static var agents: URL { support.appendingPathComponent("agents", isDirectory: true) }
    public static func prepare() throws {
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    }
}

public enum ConfigurationIO {
    public static func load(from url: URL) throws -> OrbitConfiguration {
        var config = try JSONDecoder().decode(OrbitConfiguration.self, from: Data(contentsOf: url))
        config.normalize(); return config
    }
    public static func save(_ config: OrbitConfiguration, to url: URL) throws {
        var normalized = config; normalized.normalize()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: url, options: .atomic)
    }
}
