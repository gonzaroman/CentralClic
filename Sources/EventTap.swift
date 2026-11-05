import CoreGraphics
import Foundation

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    EventTap.shared.handle(type: type, event: event)
}

/// Intercepts the system's left/right clicks and turns them into the button of the zone under the finger,
/// and applies the requested speed and direction to Magic Mouse scrolling.
/// Requires the Accessibility permission.
final class EventTap {
    static let shared = EventTap()

    private enum Phase { case down, dragged, up }

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Physical button pressed → button it is being turned into (so drag and release match the press).
    private var pending: [MouseButton: MouseButton] = [:]

    /// Reverse the direction of scrolling that comes from the Magic Mouse (set by AppSettings).
    var invertMouseScroll = false
    /// Multiplier for scrolling that comes from the Magic Mouse (set by AppSettings; 1 = unchanged).
    var scrollMultiplier: Double = 1
    /// The current scroll gesture started with a finger on the Magic Mouse.
    private var scrollFromMouse = false
    private var lineRemainder: (Double, Double) = (0, 0)
    private var pointRemainder: (Double, Double) = (0, 0)

    var isRunning: Bool { port != nil }

    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: tapCallback, userInfo: nil) else {
            appLog.error("Could not create the event tap (is the Accessibility permission missing?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        appLog.notice("Event tap active")
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .scrollWheel:
            handleScroll(event)
            return pass
        default:
            break
        }

        guard let (physical, phase) = EventTap.classify(type) else { return pass }

        switch phase {
        case .down:
            let decided = GestureEngine.shared.currentZone
            let target = decided ?? physical
            pending[physical] = target
            if target != physical { EventTap.rewrite(event, to: target, phase: .down) }
            if let decided { LiveTouches.shared.lastClick = decided }
            if target == .center { Engagement.recordMiddleClick() }
        case .dragged:
            if let target = pending[physical], target != physical {
                EventTap.rewrite(event, to: target, phase: .dragged)
            }
        case .up:
            if let target = pending.removeValue(forKey: physical), target != physical {
                EventTap.rewrite(event, to: target, phase: .up)
            }
        }
        return pass
    }

    /// Applies speed and direction to scrolling that comes from the Magic Mouse. Mouse and trackpad scroll
    /// events look the same, so a gesture that starts with a finger on the mouse is attributed to the mouse;
    /// the momentum that follows belongs to that gesture.
    private func handleScroll(_ event: CGEvent) {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        // Phases: 0 = none (plain wheel), 1 = began, 128 = may begin
        if momentum == 0 && (phase == 0 || phase == 1 || phase == 128) {
            let fromMouse = GestureEngine.shared.isTouched
            if phase == 1 {
                appLog.notice("Scroll: mouse \(fromMouse, privacy: .public), x\(self.scrollMultiplier, privacy: .public), invert \(self.invertMouseScroll, privacy: .public)")
            }
            if fromMouse != scrollFromMouse || phase != 0 { lineRemainder = (0, 0); pointRemainder = (0, 0) }
            scrollFromMouse = fromMouse
        }
        let factor = scrollMultiplier * (invertMouseScroll ? -1 : 1)
        guard scrollFromMouse, factor != 1 else { return }

        // Read everything before writing: setting one field can recompute the others.
        let d1 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let d2 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let f2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let p1 = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let p2 = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))

        // Lines and points are integers: whatever doesn't reach a whole unit is carried to the next event,
        // so small movements aren't lost at low speeds.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: EventTap.scaled(d1, factor, &lineRemainder.0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: EventTap.scaled(d2, factor, &lineRemainder.1))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: f1 * factor)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: f2 * factor)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: EventTap.scaled(p1, factor, &pointRemainder.0))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: EventTap.scaled(p2, factor, &pointRemainder.1))
    }

    private static func scaled(_ value: Double, _ factor: Double, _ remainder: inout Double) -> Int64 {
        let exact = value * factor + remainder
        let whole = exact.rounded(.towardZero)
        remainder = exact - whole
        return Int64(whole)
    }

    private static func classify(_ type: CGEventType) -> (MouseButton, Phase)? {
        switch type {
        case .leftMouseDown: return (.left, .down)
        case .leftMouseDragged: return (.left, .dragged)
        case .leftMouseUp: return (.left, .up)
        case .rightMouseDown: return (.right, .down)
        case .rightMouseDragged: return (.right, .dragged)
        case .rightMouseUp: return (.right, .up)
        default: return nil
        }
    }

    private static func eventType(for button: MouseButton, _ phase: Phase) -> CGEventType {
        switch (button, phase) {
        case (.left, .down): return .leftMouseDown
        case (.left, .dragged): return .leftMouseDragged
        case (.left, .up): return .leftMouseUp
        case (.right, .down): return .rightMouseDown
        case (.right, .dragged): return .rightMouseDragged
        case (.right, .up): return .rightMouseUp
        case (.center, .down): return .otherMouseDown
        case (.center, .dragged): return .otherMouseDragged
        case (.center, .up): return .otherMouseUp
        }
    }

    /// Changes the event's button and keeps everything else (position, click count for double clicks…).
    private static func rewrite(_ event: CGEvent, to button: MouseButton, phase: Phase) {
        event.type = eventType(for: button, phase)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    }
}
