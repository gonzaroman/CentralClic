import Foundation

/// Keeps track of which fingers are on the mouse and which zone they are in.
/// `process` is called from the MultitouchSupport thread; everything else from the main thread. All access goes through `lock`.
final class GestureEngine {
    static let shared = GestureEngine()

    private let lock = NSLock()

    // Configuration (written by AppSettings).
    private var enabled = true
    private var zones = ZoneConfig.default

    // Touch state.
    private var touches: [TouchPoint] = []
    private var zone: MouseButton?

    // Live finger view (only while the settings window is open).
    private var liveEnabled = false
    private var lastLivePush: TimeInterval = 0
    private var lastLiveCount = -1

    /// Zone a click would hit right now, or nil if no finger is on the mouse (or the app is turned off).
    /// With fingers in several zones, the leftmost wins, like macOS does with right-click.
    var currentZone: MouseButton? {
        lock.lock(); defer { lock.unlock() }
        return zone
    }

    /// true if any finger is on the Magic Mouse right now (whether or not the app is enabled).
    var isTouched: Bool {
        lock.lock(); defer { lock.unlock() }
        return !touches.isEmpty
    }

    func configure(enabled: Bool, zones: ZoneConfig) {
        lock.lock()
        self.enabled = enabled
        self.zones = zones
        refreshZone()
        lock.unlock()
    }

    func setLive(_ on: Bool) {
        lock.lock(); liveEnabled = on; lastLiveCount = -1; lock.unlock()
    }

    /// Touch frame (MultitouchSupport thread).
    func process(_ points: [TouchPoint]) {
        let now = ProcessInfo.processInfo.systemUptime
        var pushLive = false

        lock.lock()
        touches = points
        refreshZone()
        if liveEnabled && (points.count != lastLiveCount || now - lastLivePush > 1.0 / 30) {
            pushLive = true
            lastLivePush = now
            lastLiveCount = points.count
        }
        lock.unlock()

        if pushLive {
            DispatchQueue.main.async { LiveTouches.shared.points = points }
        }
    }

    /// Recomputes the zone. Call with `lock` held.
    private func refreshZone() {
        zone = enabled
            ? touches.map { zones.button(atX: $0.x) }.min { $0.spatialOrder < $1.spatialOrder }
            : nil
    }
}
