import Foundation
import IOKit.hidsystem

/// Mouse pointer speed and acceleration, through the macOS HID event system.
/// These are the same values System Settings → Mouse writes, but here the speed can go past the maximum.
/// They only affect mice: the trackpad uses its own keys.
/// (Scrolling speed and direction are applied in EventTap, to the Magic Mouse only.)
final class MouseTuning {
    static let shared = MouseTuning()

    static let pointerRange: ClosedRange<Double> = 0...10
    /// Maximum of the pointer speed slider in System Settings.
    static let systemPointerMax = 3.0
    /// Scrolling multiplier (1 = same as macOS).
    static let scrollMultiplierRange: ClosedRange<Double> = 0.2...5

    private enum HIDKey {
        static let pointer = "HIDMouseAcceleration"
        static let scroll = "HIDMouseScrollAcceleration"
    }

    private enum PrefKey {
        static let pointer = "com.apple.mouse.scaling"
        static let scroll = "com.apple.scrollwheel.scaling"
        static let natural = "com.apple.swipescrolldirection"
    }

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    /// Values currently set in macOS (its global preferences).
    var systemPointerSpeed: Double { MouseTuning.globalDouble(PrefKey.pointer) ?? 1.0 }
    var systemNaturalScroll: Bool { (UserDefaults.standard.object(forKey: PrefKey.natural) as? Bool) ?? true }

    func setPointerSpeed(_ value: Double) { set(HIDKey.pointer, value) }
    func restorePointerSpeed() { set(HIDKey.pointer, systemPointerSpeed) }

    /// Turns pointer acceleration off. A negative acceleration (-1) is how the HID system has always meant
    /// "no acceleration": the pointer moves the same distance for the same hand movement, at a fixed speed.
    /// (The key macOS itself uses for this, HIDUseLinearScalingMouseAcceleration, can only be set by the
    /// system: it rejects it from regular apps.)
    func setAccelerationOff() { set(HIDKey.pointer, -1) }

    /// Puts the scroll acceleration back to the macOS value. Only used to undo what an earlier version
    /// of the app changed (macOS doesn't use it for Magic Mouse touch scrolling).
    func restoreScrollAcceleration() {
        set(HIDKey.scroll, MouseTuning.globalDouble(PrefKey.scroll) ?? 0.3125)
    }

    private func set(_ key: String, _ value: Double) {
        // The HID system stores these values as 16.16 fixed point.
        setRaw(key, NSNumber(value: Int((value * 65536).rounded())))
    }

    private func setRaw(_ key: String, _ value: NSNumber) {
        let ok = IOHIDEventSystemClientSetProperty(client, key as CFString, value)
        appLog.notice("\(key, privacy: .public) = \(value, privacy: .public) (ok: \(ok, privacy: .public))")
    }

    private static func globalDouble(_ key: String) -> Double? {
        switch UserDefaults.standard.object(forKey: key) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
