import Foundation

/// Geometry shared by the hosting surface and its measured SwiftUI content.
public enum NotchLayout {
    /// The hanging island follows either the hardware cutout or the menu bar.
    /// Outline clearance is outside a physical camera, never hidden underneath it.
    public static func cameraSize(reported: CGSize, menuBarHeight: Double, screenWidth: Double, outlined: Bool = false) -> CGSize {
        let bar = menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24
        let physical = reported.width.isFinite && reported.height.isFinite && reported.width > 0 && reported.height > 0
        let border = physical && outlined ? 2.0 : 0
        return CGSize(width: min(screenWidth * 0.7, physical ? reported.width + border * 2 : bar * 180 / 32),
                      height: physical ? min(64, max(reported.height, bar) + border) : bar)
    }

    public enum ActivityWidth: Equatable {
        case timer, agent, music, notice, notification
    }

    /// A closed activity adds equal wings to the camera. Each type has its own
    /// readable limits; constrained menu space can narrow agents but hides timers.
    public static func compactSize(cameraSize: CGSize, requiredWing: Double = 0, availableWing: Double = 0,
                                   activity: ActivityWidth = .notice, screenWidth: Double = 10_000) -> CGSize {
        guard requiredWing.isFinite, requiredWing > 0, availableWing.isFinite else { return cameraSize }
        let lower: Double = activity == .music ? min(44, requiredWing) : 44
        let upper: Double = activity == .timer ? 64 : activity == .agent ? 80 : activity == .music ? requiredWing : activity == .notification ? 190 : 104
        let needed = min(upper, max(lower, ceil(requiredWing)))
        let threshold = activity == .timer ? 64 : lower
        let room = availableWing >= threshold ? floor(min(needed, availableWing)) : 0
        let widthLimit = max(0, (screenWidth - 24 - cameraSize.width) / 2)
        let wing = min(room, widthLimit)
        return CGSize(width: cameraSize.width + (wing >= lower ? wing * 2 : 0), height: cameraSize.height)
    }

    public static func compactTextSize(height: Double) -> Double { max(1, min(16, height - 6)) }
    public static func compactIconSize(height: Double) -> Double { max(1, min(20, height - 10)) }
    public static func compactAgentTextSize(height: Double) -> Double { max(1, min(15, height - 7)) }
    public static func cornerRadius(height: Double) -> Double { min(28, height * 0.34) }
    public static func shoulder(height: Double) -> Double { min(10, height * 0.19) }

    /// Insets are the smallest clearance between a content box and the rounded
    /// silhouette. Rounded marks fit nearer the edge than rectangular text.
    public static func compactInset(height: Double, contentHeight: Double, radius: Double = 0, gap: Double = 5) -> Double {
        let corner = cornerRadius(height: height), shoulder = shoulder(height: height)
        let reach = corner - radius - gap
        let drop = corner - radius - (height - contentHeight) / 2
        guard reach > 0, drop > 0 else { return shoulder + gap }
        let horizontal = sqrt(max(0, reach * reach - drop * drop))
        return max(shoulder + gap, shoulder + corner - radius - horizontal)
    }

    public static func musicArtworkSide(height: Double) -> Double { max(0, min(26, height - 10)) }
    public static func musicArtworkRadius(height: Double) -> Double {
        let side = musicArtworkSide(height: height)
        guard height - side <= 20 else { return side * 0.28 }
        return min(side / 2, max(side * 0.2, cornerRadius(height: height) - (height - side) / 2))
    }
    public static func musicArtworkInset(height: Double) -> Double {
        let side = musicArtworkSide(height: height)
        return compactInset(height: height, contentHeight: side, radius: musicArtworkRadius(height: height),
                            gap: height - side <= 20 ? (height - side) / 2 : 5)
    }
    public static let musicBarsWidth = 21.78
    public static func musicWing(height: Double, physicalCamera: Bool) -> Double {
        guard physicalCamera else { return 56 }
        let barsInset = compactInset(height: height, contentHeight: min(16, max(6, height - 10)), radius: 0.9)
        return ceil(max(musicArtworkSide(height: height) + musicArtworkInset(height: height), musicBarsWidth + barsInset))
    }

    /// The chooser reserves the widest single or paired strip, even when another
    /// choice is selected. Its deeper shoulders add 24 points on either side.
    public static func pickerWidth(stripWidths: [Double], count: Int, labelWidth: Double, screenWidth: Double) -> Double {
        let columns = Double(min(3, max(1, count)))
        let choices = columns * (labelWidth + 48) + (columns - 1) * 6 + 48
        return min(max((stripWidths.max() ?? 0) + 48, choices), max(1, screenWidth - 24))
    }

    public static func compactDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "∞" }
        let minutes = Int(min(525_600, max(1, ceil(seconds / 60))))
        return minutes >= 60 ? (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))") : "\(minutes)m"
    }

    /// All rectangles use AppKit screen coordinates, including negative origins.
    public static func menuSideRoom(screen: CGRect, cameraWidth: Double, menuItems: [CGRect], statusItems: [CGRect]) -> Double? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - 64, width: screen.width, height: 64)
        let menus = menuItems.filter { $0.intersects(bar) }
        guard !menus.isEmpty else { return nil }
        let cameraLeft = screen.midX - cameraWidth / 2, cameraRight = screen.midX + cameraWidth / 2
        var left = screen.minX, right = screen.maxX
        for rect in menus + statusItems.filter({ $0.intersects(bar) }) {
            if rect.maxX <= cameraLeft { left = max(left, rect.maxX) }
            else if rect.minX >= cameraRight { right = min(right, rect.minX) }
            else { return 0 }
        }
        return max(0, floor(min(cameraLeft - left, right - cameraRight) - 8))
    }

    public static func expandedWidth(preferred: Double, cameraWidth: Double, screenWidth: Double, shortcutAllowance: Double) -> Double {
        min(max(1, screenWidth - shortcutAllowance - 24), max(preferred.isFinite ? preferred : 480, cameraWidth + 36))
    }

    public static func headingHeight(cameraHeight: Double) -> Double {
        max(18, cameraHeight - 10)
    }

    public static func contentBudget(screenHeight: Double, cameraHeight: Double) -> Double {
        max(1, screenHeight - 40 - headingHeight(cameraHeight: cameraHeight) - 38)
    }

    public static func fittedHeight(measured: Double, screenHeight: Double) -> Double {
        min(max(1, screenHeight - 40), max(56, ceil(measured)))
    }
}

/// Remember a display's visible menu bar through auto-hide and full-screen changes.
public struct NotchBarMeasurements {
    private var cached: [UInt32: (CGSize, Double, Double)] = [:]
    public init() {}
    public mutating func height(displayID: UInt32, size: CGSize, scale: Double, visibleGap: Double, fallback: Double) -> Double {
        let validScale = displayID != 0 && scale.isFinite && scale > 0
        let previous = cached[displayID]
        let sameDisplay = previous?.0 == size && previous?.1 == scale
        if !sameDisplay { cached.removeValue(forKey: displayID) }
        if visibleGap.isFinite && (16...64).contains(visibleGap) {
            if validScale { cached[displayID] = (size, scale, visibleGap) }
            return visibleGap
        }
        if validScale, sameDisplay, let previous { return previous.2 }
        return fallback.isFinite && (16...64).contains(fallback) ? fallback : 24
    }
}

public struct SurfacePage: Equatable {
    public let index: Int
    public let count: Int
    public let range: Range<Int>

    public init(itemCount: Int, requestedIndex: Int, capacity: Int) {
        let size = max(1, capacity), items = max(0, itemCount)
        count = max(1, (items + size - 1) / size)
        index = min(max(0, requestedIndex), count - 1)
        let start = min(items, index * size)
        range = start..<min(items, start + size)
    }
}
