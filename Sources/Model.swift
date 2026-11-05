import AppKit
import os

let appLog = Logger(subsystem: "com.gonzaroman.centralclic", category: "app")

/// Mouse button. The raw value is the CGEvent button number.
enum MouseButton: Int {
    case left = 0
    case right = 1
    case center = 2

    var title: String {
        switch self {
        case .left: return L("Left")
        case .center: return L("Middle")
        case .right: return L("Right")
        }
    }

    /// One-letter label drawn on each zone of the mouse.
    var letter: String {
        switch self {
        case .left: return L("Left zone letter")
        case .center: return L("Middle zone letter")
        case .right: return L("Right zone letter")
        }
    }

    var nsColor: NSColor {
        switch self {
        case .left: return .systemBlue
        case .center: return .systemOrange
        case .right: return .systemGreen
        }
    }

    /// Left-to-right order on the mouse.
    var spatialOrder: Int {
        switch self {
        case .left: return 0
        case .center: return 1
        case .right: return 2
        }
    }
}

/// Width of each zone, in percent. They always add up to 100.
/// The left zone never goes below `minimumLeft`: any narrower and almost every click would be a middle click,
/// so you couldn't even use the settings window to fix it. Middle and right are at least `minimum`.
struct ZoneConfig: Equatable {
    static let minimum = 10
    static let minimumLeft = 15
    static let `default` = ZoneConfig(left: 36, center: 28, right: 36)

    /// Shared scale for both sliders (left and right), so the same percentage looks the same length.
    /// The real per-side limits are enforced by AppSettings when saving.
    static let sliderRange = minimum...(100 - 2 * minimum)   // 10…80

    var left: Int
    var center: Int
    var right: Int

    var isValid: Bool {
        left + center + right == 100 && left >= ZoneConfig.minimumLeft
            && center >= ZoneConfig.minimum && right >= ZoneConfig.minimum
    }

    func width(of button: MouseButton) -> Int {
        switch button {
        case .left: return left
        case .center: return center
        case .right: return right
        }
    }

    /// Button for a normalized horizontal position (0 = left edge, 1 = right edge).
    func button(atX x: Float) -> MouseButton {
        let p = Double(x) * 100
        if p < Double(left) { return .left }
        if p < Double(left + center) { return .center }
        return .right
    }
}

/// A finger resting on the Magic Mouse, in normalized 0..1 coordinates.
struct TouchPoint: Identifiable, Equatable {
    let id: Int32
    let x: Float
    let y: Float
}
