import Foundation
import CoreGraphics

public struct NotchColor: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    public static let black = NotchColor(0, 0, 0)
    public static let silver = NotchColor(0.65, 0.68, 0.75)
    public var normalized: NotchColor {
        func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        return NotchColor(clamp(red), clamp(green), clamp(blue))
    }
    /// An opaque dark tint preserves contrast for the notch's white controls.
    public var surface: NotchColor {
        let value = normalized
        return NotchColor(value.red * 0.18, value.green * 0.18, value.blue * 0.18)
    }
}

public enum NotchShortcutPosition: String, Codable, CaseIterable {
    case left, right, bottom, hidden
    public var title: String { self == .bottom ? "Below" : rawValue.capitalized }
}

public struct NotchShortcut: Codable, Equatable, Identifiable {
    public var action: OrbitAction
    public var position: NotchShortcutPosition
    public var label: String?
    public var id: OrbitAction { action }
    public init(_ action: OrbitAction, _ position: NotchShortcutPosition, label: String? = nil) { self.action = action; self.position = position; self.label = label }
}

public struct NotchOptions: Codable, Equatable {
    public var color = NotchColor.black
    public var outlineEnabled = false
    public var outlineColor = NotchColor.silver
    public var outlineWidth = 1.0
    public var shortcutsEnabled = true
    public var shortcuts = Self.defaultShortcuts
    public var showInbox = true
    public var showAgents = true
    public var showTimers = true
    public var showMusic = true
    public var showKeepAwake = true
    public var showClipboard = true
    public var showNotifications = true
    public var animateActivityIcons = true
    public var allowActivityOverMenus = true
    public static let maximumSideCount = 6
    public static let maximumBottomCount = 12
    public static var availableShortcuts: [OrbitAction] { OrbitAction.surfaceTools + [.settings] }
    public static let defaultShortcuts: [NotchShortcut] = [
        .init(.agents, .left), .init(.music, .left), .init(.timer, .left), .init(.clipboard, .left), .init(.sound, .left),
        .init(.files, .right), .init(.textTools, .right), .init(.scratchpad, .right), .init(.keepAwake, .right), .init(.settings, .right),
        .init(.notifications, .hidden)
    ]
    public init() {}
    public func actions(at position: NotchShortcutPosition) -> [OrbitAction] {
        shortcuts.filter { $0.position == position }.map(\.action)
    }
    public func visibleActions(at position: NotchShortcutPosition) -> [OrbitAction] {
        shortcutsEnabled && position != .hidden ? actions(at: position) : []
    }
    public func shortcutTitle(_ action: OrbitAction) -> String {
        let label = shortcuts.first { $0.action == action }?.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? action.title : label
    }
    public func hasRoom(at position: NotchShortcutPosition, moving action: OrbitAction? = nil) -> Bool {
        if position == .hidden { return true }
        let count = shortcuts.filter { $0.position == position && $0.action != action }.count
        return count < (position == .bottom ? Self.maximumBottomCount : Self.maximumSideCount)
    }
    /// Move by tool identity so an open editor survives reordering and hidden entries.
    @discardableResult public mutating func moveShortcut(_ action: OrbitAction, to position: NotchShortcutPosition, before next: OrbitAction? = nil) -> Bool {
        guard Self.availableShortcuts.contains(action), hasRoom(at: position, moving: action) else { return false }
        let previous = shortcuts
        var item = shortcuts.first { $0.action == action } ?? NotchShortcut(action, position)
        shortcuts.removeAll { $0.action == action }; item.position = position
        if let next, let index = shortcuts.firstIndex(where: { $0.action == next && $0.position == position }) { shortcuts.insert(item, at: index) }
        else if let last = shortcuts.lastIndex(where: { $0.position == position }) { shortcuts.insert(item, at: last + 1) }
        else { shortcuts.append(item) }
        return previous != shortcuts
    }
    @discardableResult public mutating func reorderShortcut(_ action: OrbitAction, by offset: Int) -> Bool {
        guard let index = shortcuts.firstIndex(where: { $0.action == action }) else { return false }
        let indices = shortcuts.indices.filter { shortcuts[$0].position == shortcuts[index].position }
        guard let rank = indices.firstIndex(of: index), indices.indices.contains(rank + offset) else { return false }
        shortcuts.swapAt(index, indices[rank + offset]); return true
    }
    @discardableResult public mutating func replaceShortcut(_ action: OrbitAction, with replacement: OrbitAction) -> Bool {
        guard action != replacement, Self.availableShortcuts.contains(replacement), let old = shortcuts.first(where: { $0.action == action }),
              !shortcuts.contains(where: { $0.action == replacement && $0.position != .hidden }) else { return false }
        shortcuts.removeAll { $0.action == replacement }
        guard let index = shortcuts.firstIndex(where: { $0.action == action }) else { return false }
        shortcuts[index] = NotchShortcut(replacement, old.position, label: old.label)
        shortcuts.append(NotchShortcut(action, .hidden))
        return true
    }
    public func showsActivity(for action: OrbitAction) -> Bool {
        switch action {
        case .agents: return showAgents
        case .timer: return showTimers
        case .music: return showMusic
        case .keepAwake: return showKeepAwake
        case .clipboard: return showClipboard
        case .notifications: return showNotifications
        default: return false
        }
    }
    public mutating func normalize() {
        color = color.normalized; outlineColor = outlineColor.normalized
        outlineWidth = outlineWidth.isFinite ? min(3, max(0.5, outlineWidth)) : 1
        let allowed = Set(Self.availableShortcuts)
        var seen = Set<OrbitAction>(), counts: [NotchShortcutPosition: Int] = [:]
        shortcuts = shortcuts.compactMap { item in
            guard allowed.contains(item.action), seen.insert(item.action).inserted else { return nil }
            var item = item
            item.label = item.label.map { String($0.prefix(48)) }
            if item.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { item.label = nil }
            if [.left, .right].contains(item.position) {
                if counts[item.position, default: 0] >= Self.maximumSideCount { item.position = .bottom }
                else { counts[item.position, default: 0] += 1 }
            }
            if item.position == .bottom {
                if counts[.bottom, default: 0] >= Self.maximumBottomCount { item.position = .hidden }
                else { counts[.bottom, default: 0] += 1 }
            }
            return item
        }
        // Missing entries stay hidden, including explicit empty imported layouts.
        shortcuts += Self.defaultShortcuts.filter { !seen.contains($0.action) }.map { NotchShortcut($0.action, .hidden) }
    }
    private enum CodingKeys: String, CodingKey {
        case color, outlineEnabled, outlineColor, outlineWidth, shortcutsEnabled, shortcuts, showInbox, showAgents, showTimers, showMusic, showKeepAwake, showClipboard, showNotifications, animateActivityIcons, allowActivityOverMenus
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(NotchColor.self, forKey: .color) ?? color
        outlineEnabled = try c.decodeIfPresent(Bool.self, forKey: .outlineEnabled) ?? outlineEnabled
        outlineColor = try c.decodeIfPresent(NotchColor.self, forKey: .outlineColor) ?? outlineColor
        outlineWidth = try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? outlineWidth
        shortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? shortcutsEnabled
        shortcuts = try c.decodeIfPresent([NotchShortcut].self, forKey: .shortcuts) ?? shortcuts
        showInbox = try c.decodeIfPresent(Bool.self, forKey: .showInbox) ?? showInbox
        showAgents = try c.decodeIfPresent(Bool.self, forKey: .showAgents) ?? showAgents
        showTimers = try c.decodeIfPresent(Bool.self, forKey: .showTimers) ?? showTimers
        showMusic = try c.decodeIfPresent(Bool.self, forKey: .showMusic) ?? showMusic
        showKeepAwake = try c.decodeIfPresent(Bool.self, forKey: .showKeepAwake) ?? showKeepAwake
        showClipboard = try c.decodeIfPresent(Bool.self, forKey: .showClipboard) ?? showClipboard
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? showNotifications
        animateActivityIcons = try c.decodeIfPresent(Bool.self, forKey: .animateActivityIcons) ?? animateActivityIcons
        allowActivityOverMenus = try c.decodeIfPresent(Bool.self, forKey: .allowActivityOverMenus) ?? allowActivityOverMenus
        normalize()
    }
}

/// Actual button bounds determine both the canvas and input region; hidden rails reserve no space.
public struct NotchShortcutLayout {
    public static func bottomAllowance(count: Int) -> Double {
        let rows = (max(0, count) + 5) / 6
        return rows == 0 ? 0 : 10 + Double(rows * 44 + (rows - 1) * 8)
    }
    public let body: CGRect
    public let left: CGRect
    public let right: CGRect
    public let bottom: CGRect
    public let canvas: CGSize
    public init(bodySize: CGSize, railTop: Double, options: NotchOptions) {
        let leftCount = options.visibleActions(at: .left).count
        let rightCount = options.visibleActions(at: .right).count
        let bottomCount = options.visibleActions(at: .bottom).count
        let margin = leftCount + rightCount > 0 ? 64.0 : 0.0
        func sideHeight(_ count: Int) -> Double { count == 0 ? 0 : Double(count * 44 + (count - 1) * 8) }
        body = CGRect(x: margin, y: 0, width: bodySize.width, height: bodySize.height)
        left = leftCount == 0 ? .zero : CGRect(x: margin - 54, y: railTop, width: 44, height: sideHeight(leftCount))
        right = rightCount == 0 ? .zero : CGRect(x: margin + bodySize.width + 10, y: railTop, width: 44, height: sideHeight(rightCount))
        let columns = min(6, bottomCount), rows = (bottomCount + 5) / 6
        let bottomWidth = sideHeight(columns)
        bottom = bottomCount == 0 ? .zero : CGRect(x: margin + (bodySize.width - bottomWidth) / 2, y: bodySize.height + 10, width: bottomWidth, height: sideHeight(rows))
        canvas = CGSize(width: bodySize.width + margin * 2, height: max(bodySize.height, left.maxY, right.maxY, bottom.maxY))
    }
}
