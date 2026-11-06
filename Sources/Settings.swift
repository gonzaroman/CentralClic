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

    /// Whether pointer acceleration is off in macOS (System Settings → Mouse → Advanced). Read-only for the app;
    /// refreshed while the settings window is open.
    @Published private(set) var systemAccelerationOff = false

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
        systemAccelerationOff = tuning.systemAccelerationOff
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
        if let pointerSpeed { tuning.setPointerSpeed(pointerSpeed) }
        EventTap.shared.scrollMultiplier = scrollMultiplier ?? 1
        let wantNatural = naturalScroll ?? tuning.systemNaturalScroll
        EventTap.shared.invertMouseScroll = wantNatural != tuning.systemNaturalScroll
        objectWillChange.send()
    }

    /// Puts the macOS values back (when the app is turned off or quits).
    func restoreSystemMotion() {
        if pointerSpeed != nil { tuning.restorePointerSpeed() }
        EventTap.shared.invertMouseScroll = false
        EventTap.shared.scrollMultiplier = 1
    }

    /// Re-reads the macOS settings the app shows but can't change.
    func refreshSystemState() {
        let off = tuning.systemAccelerationOff
        if off != systemAccelerationOff { systemAccelerationOff = off }
    }

    /// The setup closest to how mice feel on Windows: a fast pointer and classic scrolling. It works best
    /// with macOS pointer acceleration off, which only System Settings can change, so it opens it if needed.
    func optimize() {
        pointerSpeed = MouseTuning.optimizedPointerSpeed
        naturalScroll = false
        refreshSystemState()
        if !systemAccelerationOff { tuning.openMouseSettings() }
    }

    /// Cleans up settings from earlier versions.
    private func migrateOldSettings() {
        // The old scrolling speed was applied through HID: put the macOS value back.
        if defaults.object(forKey: "scrollSpeed") != nil {
            tuning.restoreScrollAcceleration()
            defaults.removeObject(forKey: "scrollSpeed")
        }
        // Version 1.0.0 had its own "no acceleration" option (acceleration -1, at a fixed, slow speed).
        // It was replaced by the macOS setting; drop it and give the pointer a normal speed again.
        if defaults.object(forKey: Key.disableAcceleration) != nil {
            let wasOn = defaults.bool(forKey: Key.disableAcceleration)
            defaults.removeObject(forKey: Key.disableAcceleration)
            if wasOn && pointerSpeed == nil { tuning.restorePointerSpeed() }
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

