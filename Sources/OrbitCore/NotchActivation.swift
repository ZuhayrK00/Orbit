import Foundation
import CoreGraphics

public enum NotchActivation {
    /// The visible island owns its exact horizontal span, including the screen's
    /// final pixel. The expanded panel is also the retention area while open.
    public static func contains(point: CGPoint, screen: CGRect, panel: CGRect) -> Bool {
        guard !screen.isEmpty, !panel.isEmpty,
              point.x >= screen.minX, point.x <= screen.maxX,
              point.y >= screen.minY, point.y <= screen.maxY + 1 else { return false }
        return point.x >= panel.minX && point.x <= panel.maxX
            && point.y >= panel.minY && point.y <= min(panel.maxY, screen.maxY) + 1
    }
}
