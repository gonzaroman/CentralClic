import Foundation
import ServiceManagement

/// User preferences, stored in UserDefaults. Only used from the main thread.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let enabled = "enabled"
        static let zoneLeft = "zoneLeft"
        static let zoneCenter = "zoneCenter"
        static let zoneRight = "zoneRight"
        static let pointerSpeed = "pointerSpeed"
        static let scrollMultiplier = "scrollMultiplier"
        static let naturalScroll = "naturalScroll"
        static let disableAcceleration = "disableAcceleration"
        static let launchedBefore = "launchedBefore"
    }

    private let defaults = UserDefaults.standard
    private let tuning = MouseTuning.shared

    /// Master switch: when off, the app changes no clicks, speeds or direction.
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Key.enabled)
            push()
            if enabled { applyMotion() } else { restoreSystemMotion() }
        }
    }

    @Published private(set) var zones: ZoneConfig {
        didSet {
            defaults.set(zones.left, forKey: Key.zoneLeft)
            defaults.set(zones.center, forKey: Key.zoneCenter)
            defaults.set(zones.right, forKey: Key.zoneRight)
            push()
        }
    }

    /// Custom pointer speed, or nil to keep the macOS one.
    @Published var pointerSpeed: Double? {
        didSet {
            store(pointerSpeed, Key.pointerSpeed)
            if pointerSpeed == nil && oldValue != nil { tuning.restorePointerSpeed() }
            applyMotion()
        }
    }

    /// Turn off pointer acceleration. The pointer then moves at a fixed speed, so `pointerSpeed` doesn't apply.
    @Published var disableAcceleration: Bool {
        didSet {
            defaults.set(disableAcceleration, forKey: Key.disableAcceleration)
            // Turning acceleration back on without a custom speed: go back to the macOS speed.
            if oldValue && !disableAcceleration && pointerSpeed == nil { tuning.restorePointerSpeed() }
            applyMotion()
        }
    }

    /// Magic Mouse scrolling multiplier (1 = same as macOS), or nil to leave it alone.
    @Published var scrollMultiplier: Double? {
        didSet { store(scrollMultiplier, Key.scrollMultiplier); applyMotion() }
    }

    /// Magic Mouse scroll direction (true = natural), or nil to follow macOS.
    @Published var naturalScroll: Bool? {
        didSet {
            if let naturalScroll { defaults.set(naturalScroll, forKey: Key.naturalScroll) } else { defaults.removeObject(forKey: Key.naturalScroll) }
            applyMotion()
        }
    }

    private init() {
        defaults.register(defaults: [Key.enabled: true])
        enabled = defaults.bool(forKey: Key.enabled)
        let stored = ZoneConfig(left: defaults.integer(forKey: Key.zoneLeft),
                                center: defaults.integer(forKey: Key.zoneCenter),
                                right: defaults.integer(forKey: Key.zoneRight))
        zones = stored.isValid ? stored : .default
        pointerSpeed = (defaults.object(forKey: Key.pointerSpeed) as? Double).map { min(max($0, MouseTuning.pointerRange.lowerBound), MouseTuning.pointerRange.upperBound) }
        scrollMultiplier = (defaults.object(forKey: Key.scrollMultiplier) as? Double).map { min(max($0, MouseTuning.scrollMultiplierRange.lowerBound), MouseTuning.scrollMultiplierRange.upperBound) }
        naturalScroll = defaults.object(forKey: Key.naturalScroll) as? Bool
        disableAcceleration = defaults.bool(forKey: Key.disableAcceleration)
        migrateOldSettings()
        push()
    }

    /// true only the first time the app is opened.
    func consumeFirstLaunch() -> Bool {
        if defaults.bool(forKey: Key.launchedBefore) { return false }
        defaults.set(true, forKey: Key.launchedBefore)
        return true
    }

    private func push() {
        GestureEngine.shared.configure(enabled: enabled, zones: zones)
    }

    private func store(_ value: Double?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    // MARK: Pointer and scrolling

    /// Applies speeds and direction. Called again when the mouse connects, on wake,
    /// and when macOS changes its own scroll direction setting.
    func applyMotion() {
        guard enabled else {
            EventTap.shared.invertMouseScroll = false
            EventTap.shared.scrollMultiplier = 1
            return
        }
        // Without acceleration the speed is fixed by macOS, so a custom speed only applies with acceleration on.
        if disableAcceleration {
            tuning.setAccelerationOff()
        } else if let pointerSpeed {
            tuning.setPointerSpeed(pointerSpeed)
        }
        EventTap.shared.scrollMultiplier = scrollMultiplier ?? 1
        let wantNatural = naturalScroll ?? tuning.systemNaturalScroll
        EventTap.shared.invertMouseScroll = wantNatural != tuning.systemNaturalScroll
        objectWillChange.send()
    }

    /// Puts the macOS values back (when the app is turned off or quits).
    func restoreSystemMotion() {
        if disableAcceleration || pointerSpeed != nil { tuning.restorePointerSpeed() }
        EventTap.shared.invertMouseScroll = false
        EventTap.shared.scrollMultiplier = 1
    }

    /// Cleans up settings from earlier versions.
    private func migrateOldSettings() {
        // The old scrolling speed was applied through HID: put the macOS value back.
        if defaults.object(forKey: "scrollSpeed") != nil {
            tuning.restoreScrollAcceleration()
            defaults.removeObject(forKey: "scrollSpeed")
        }
        for key in ["mode", "highlightPointer", "highlightSize"] { defaults.removeObject(forKey: key) }
    }

    // MARK: Zones

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

    /// Changes the left width; the right stays and the middle takes the rest.
    func setLeft(_ value: Int) {
        let l = AppSettings.clamp(value, ZoneConfig.minimumLeft, 100 - zones.right - ZoneConfig.minimum)
        zones = ZoneConfig(left: l, center: 100 - l - zones.right, right: zones.right)
    }

    /// Changes the right width; the left stays and the middle takes the rest.
    func setRight(_ value: Int) {
        let r = AppSettings.clamp(value, ZoneConfig.minimum, 100 - zones.left - ZoneConfig.minimum)
        zones = ZoneConfig(left: zones.left, center: 100 - zones.left - r, right: r)
    }

    /// Moves the line between left and middle (percent from the left edge).
    func moveLeftDivider(to percent: Int) { setLeft(percent) }

    /// Moves the line between middle and right (percent from the left edge).
    func moveRightDivider(to percent: Int) { setRight(100 - percent) }

    func resetZones() { zones = .default }

    // MARK: Open at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            appLog.error("Open at login: \(error.localizedDescription, privacy: .public)")
        }
        objectWillChange.send()
    }
}

/// Live state shown by the settings window. Only touched from the main thread.
final class LiveTouches: ObservableObject {
    static let shared = LiveTouches()
    @Published var points: [TouchPoint] = []
    @Published var lastClick: MouseButton?
    @Published var connectedMice = 0
    @Published var accessibilityGranted = false
}

/// Before it was renamed, the app was called CentralClic, with the bundle id com.gonzaroman.centralclic.
/// On the first launch under the new id, copy those settings so nobody loses their zones and speeds.
enum LegacySettings {
    private static let oldDomain = "com.gonzaroman.centralclic"
    private static let keys = ["enabled", "zoneLeft", "zoneCenter", "zoneRight", "pointerSpeed", "scrollMultiplier",
                               "naturalScroll", "disableAcceleration", "launchedBefore", "middleClickCount",
                               "askedForSupport", "checkForUpdates", "lastUpdateCheck", "notifiedUpdateVersion"]

    /// Must run before AppSettings, Updater or Engagement read their values.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "migratedFromCentralClic") == nil else { return }
        defaults.set(true, forKey: "migratedFromCentralClic")
        guard let old = UserDefaults(suiteName: oldDomain) else { return }
        var copied = 0
        for key in keys {
            if let value = old.object(forKey: key), defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                copied += 1
            }
        }
        if copied > 0 { appLog.notice("Copied \(copied, privacy: .public) settings from CentralClic") }
    }
}
