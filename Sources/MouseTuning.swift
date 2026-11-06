import AppKit
import IOKit.hidsystem

/// Mouse pointer speed and acceleration, through the macOS HID event system.
/// These are the same values System Settings → Mouse writes, but here the speed can go past the maximum.
/// They only affect mice: the trackpad uses its own keys.
/// (Scrolling speed and direction are applied in EventTap, to the Magic Mouse only.)
final class MouseTuning {
    static let shared = MouseTuning()

    static let pointerRange: ClosedRange<Double> = 0...20
    /// Maximum of the pointer speed slider in System Settings.
    static let systemPointerMax = 3.0
    /// Speed set by Optimize. Tested on a Magic Mouse; it applies on top of macOS's own
    /// "no acceleration" mode, which is the closest to how mice feel on Windows.
    static let optimizedPointerSpeed = 10.0
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
        /// System Settings → Mouse → Advanced → Pointer acceleration (true = acceleration off).
        static let linear = "com.apple.mouse.linear"
    }

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    /// Values currently set in macOS (its global preferences).
    var systemPointerSpeed: Double { MouseTuning.globalDouble(PrefKey.pointer) ?? 1.0 }
    var systemNaturalScroll: Bool { (UserDefaults.standard.object(forKey: PrefKey.natural) as? Bool) ?? true }

    /// true if pointer acceleration is turned off in macOS. Apps can't change it: macOS rejects
    /// HIDUseLinearScalingMouseAcceleration from anything but the system, and the Magic Mouse's own HID
    /// service is hidden from apps. So the app reads it and sends the user to System Settings.
    var systemAccelerationOff: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return (UserDefaults.standard.object(forKey: PrefKey.linear) as? NSNumber)?.boolValue ?? false
    }

    /// Opens System Settings → Mouse, where pointer acceleration is turned off (under Advanced).
    func openMouseSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension")!)
    }

    func setPointerSpeed(_ value: Double) { set(HIDKey.pointer, value) }
    func restorePointerSpeed() { set(HIDKey.pointer, systemPointerSpeed) }

    /// Puts the scroll acceleration back to the macOS value. Only used to undo what an earlier version
    /// of the app changed (macOS doesn't use it for Magic Mouse touch scrolling).
    func restoreScrollAcceleration() {
        set(HIDKey.scroll, MouseTuning.globalDouble(PrefKey.scroll) ?? 0.3125)
    }

    /// Last value written for each key, so moving an unrelated slider doesn't rewrite it dozens of times a second.
    private var applied: [String: Int] = [:]

    /// Forgets what was written, so the next call writes again. Call it when a mouse (re)connects:
    /// a new device starts with the macOS values.
    func forgetApplied() { applied.removeAll() }

    private func set(_ key: String, _ value: Double) {
        // The HID system stores these values as 16.16 fixed point.
        let fixed = Int((value * 65536).rounded())
        guard applied[key] != fixed else { return }
        applied[key] = fixed
        setRaw(key, NSNumber(value: fixed))
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
