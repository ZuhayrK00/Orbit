import Foundation

public enum WheelGeometry {
    /// Index zero is at 12 o'clock. Coordinates have their origin at the top left.
    public static func index(x: Double, y: Double, diameter: Double, count: Int) -> Int? {
        guard count > 0, diameter > 0 else { return nil }
        let dx = x - diameter / 2, dy = y - diameter / 2
        let distance = hypot(dx, dy)
        guard distance >= diameter * 0.205, distance <= diameter * 0.49 else { return nil }
        let turn = Double.pi * 2
        let angle = (atan2(dy, dx) + Double.pi / 2 + turn).truncatingRemainder(dividingBy: turn)
        let sector = turn / Double(count)
        return Int(floor((angle + sector / 2).truncatingRemainder(dividingBy: turn) / sector)) % count
    }
    public static func center(index: Int, count: Int, diameter: Double) -> (x: Double, y: Double) {
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(count, 1))
        let radius = diameter * 0.335
        return (diameter / 2 + cos(angle) * radius, diameter / 2 + sin(angle) * radius)
    }
}
