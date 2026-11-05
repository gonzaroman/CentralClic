import Foundation
import IOKit

/// Receives touch frames from the private MultitouchSupport framework.
/// Runs on the framework's own thread, never on the main thread.
private let contactCallback: MTContactCallbackFunction = { _, fingers, count, _, _ in
    var points: [TouchPoint] = []
    if let fingers, count > 0 {
        points.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let f = fingers[i]
            // 3 = touch starts, 4 = touching. Other states are fingers approaching or leaving.
            if f.state == 3 || f.state == 4 {
                points.append(TouchPoint(id: f.identifier,
                                         x: f.normalized.position.x,
                                         y: f.normalized.position.y))
            }
        }
    }
    GestureEngine.shared.process(points)
    return 0
}

/// Finds the connected Magic Mice and listens to their fingers.
/// Functions are loaded with dlopen because the Command Line Tools don't ship the private framework for linking.
final class Multitouch {
    static let shared = Multitouch()

    /// MultitouchSupport families that belong to a Magic Mouse (trackpads are 98–106, 128–130…).
    private static let mouseFamilies: Set<Int32> = [112, 113]

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer?, MTContactCallbackFunction?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias FamilyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> Int32
    private typealias ServiceFn = @convention(c) (UnsafeMutableRawPointer?) -> io_service_t

    private var createList: CreateListFn?
    private var register: RegisterFn?
    private var unregister: RegisterFn?
    private var startDevice: StartFn?
    private var stopDevice: StopFn?
    private var getFamily: FamilyFn?
    private var getService: ServiceFn?

    private var deviceList: CFMutableArray?
    private var mice: [UnsafeMutableRawPointer] = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pendingRescan: DispatchWorkItem?

    /// Called on the main thread with the number of active Magic Mice.
    var onDevicesChanged: ((Int) -> Void)?

    var connectedMice: Int { mice.count }

    /// Loads the framework. Returns false if this macOS doesn't have it.
    func load() -> Bool {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            appLog.error("Could not load MultitouchSupport")
            return false
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        createList = sym("MTDeviceCreateList", CreateListFn.self)
        register = sym("MTRegisterContactFrameCallback", RegisterFn.self)
        unregister = sym("MTUnregisterContactFrameCallback", RegisterFn.self)
        startDevice = sym("MTDeviceStart", StartFn.self)
        stopDevice = sym("MTDeviceStop", StopFn.self)
        getFamily = sym("MTDeviceGetFamilyID", FamilyFn.self)
        getService = sym("MTDeviceGetService", ServiceFn.self)
        let ok = createList != nil && register != nil && startDevice != nil && getFamily != nil
        if !ok { appLog.error("MultitouchSupport is missing functions") }
        return ok
    }

    /// Stops everything and looks for Magic Mice again.
    func rescan() {
        stopAll()
        guard let createList, let register, let startDevice else { return }
        guard let list = createList()?.takeRetainedValue() else { return }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var family: Int32 = 0
            _ = getFamily?(device, &family)
            let parser = parserType(of: device)
            let isMouse = Multitouch.mouseFamilies.contains(family) || parser == 2000
            appLog.notice("Multitouch device: family \(family, privacy: .public), parser \(parser, privacy: .public), mouse: \(isMouse, privacy: .public)")
            guard isMouse else { continue }
            register(device, contactCallback)
            startDevice(device, 0)
            mice.append(device)
        }
        GestureEngine.shared.process([])
        let count = mice.count
        DispatchQueue.main.async { self.onDevicesChanged?(count) }
    }

    func stopAll() {
        for device in mice {
            unregister?(device, contactCallback)
            stopDevice?(device)
        }
        mice.removeAll()
        deviceList = nil
    }

    /// Looks for devices again after a short delay, coalescing bursts of notifications.
    func scheduleRescan(after delay: TimeInterval = 1.0) {
        pendingRescan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        pendingRescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Notifies when any multitouch device connects or disconnects (e.g. when the mouse is turned on).
    func watchDevices() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                           .defaultMode)
        let callback: IOServiceMatchingCallback = { _, iterator in
            Multitouch.drain(iterator)
            Multitouch.shared.scheduleRescan()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"),
                                                          callback, nil, &iterator)
            if result == KERN_SUCCESS {
                Multitouch.drain(iterator) // must be drained once to arm the notification
                iterators.append(iterator)
            }
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        var obj = IOIteratorNext(iterator)
        while obj != 0 {
            IOObjectRelease(obj)
            obj = IOIteratorNext(iterator)
        }
    }

    private func parserType(of device: UnsafeMutableRawPointer) -> Int {
        guard let getService else { return 0 }
        let service = getService(device)
        guard service != 0,
              let value = IORegistryEntryCreateCFProperty(service, "parser-type" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
        else { return 0 }
        return value.intValue
    }
}
