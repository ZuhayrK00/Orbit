import Foundation

/// Explicit tool choices survive closing; automatic notices are temporary views.
public struct NotchNavigation: Equatable {
    public private(set) var current: OrbitAction
    public private(set) var remembered: OrbitAction
    public private(set) var isShowingNotification = false

    public init(savedTool: String? = nil) {
        let tool = savedTool.flatMap(OrbitAction.init(rawValue:))?.utilitySection ?? .agents
        current = tool; remembered = tool; isShowingNotification = false
    }
    public mutating func select(_ action: OrbitAction) {
        guard let tool = action.utilitySection else { return }
        current = tool; remembered = tool; isShowingNotification = false
    }
    public mutating func reopen() { current = remembered; isShowingNotification = false }
    public mutating func showHome() { current = .home; isShowingNotification = false }
    public mutating func showNotification() { current = .notifications; isShowingNotification = true }
}
