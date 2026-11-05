// Renders the settings window to PNG files for the README: every tab, in light and dark mode.
// Built together with the app sources by scripts/make-screenshots.sh. It only draws views: it doesn't
// create the event tap or change any mouse setting.
import AppKit
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

// Live state shown in the pictures: mouse connected, permission granted, two fingers resting, last click = middle.
let live = LiveTouches.shared
live.connectedMice = 1
live.accessibilityGranted = true
live.lastClick = .center
live.points = [TouchPoint(id: 1, x: 0.5, y: 0.66), TouchPoint(id: 2, x: 0.83, y: 0.55)]

/// A window that always draws as the active one, so switches and sliders show their accent color
/// without stealing focus from the app you are using.
final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// Image of one of our own windows from the window server. CGWindowListCreateImage is marked unavailable in
/// recent SDKs, so it is looked up at run time; capturing your own window needs no screen recording permission.
func windowServerImage(_ window: NSWindow) -> CGImage? {
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
          let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
    let create = unsafeBitCast(symbol, to: Fn.self)
    // optionIncludingWindow = 8; boundsIgnoreFraming (1) + bestResolution (8) = 9
    return create(.null, 8, UInt32(window.windowNumber), 9)?.takeRetainedValue()
}

/// Draws the window (with its title bar) at 2x, with rounded corners and a soft shadow on a transparent canvas.
func render(_ tab: SettingsTab, dark: Bool, to name: String) throws {
    let host = NSHostingView(rootView: SettingsView(initialTab: tab))
    let window = ActiveLookingWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "CentralClic"
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000)) // off screen
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    let view = window.contentView!.superview! // includes the title bar
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let scale: CGFloat = 2
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    if let image = windowServerImage(window) {
        // Exactly what the window server draws (tab bar, slider colors…).
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        // Fallback: render the Core Animation layer tree. The context already maps points to pixels.
        view.layer!.render(in: NSGraphicsContext(bitmapImageRep: rep)!.cgContext)
    }
    window.orderOut(nil)

    // Compose: padding for the shadow, rounded window corners.
    let pad: CGFloat = 40
    let canvasSize = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * scale), pixelsHigh: Int(canvasSize.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    out.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let frame = NSRect(x: pad, y: pad, width: size.width, height: size.height)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    rep.draw(in: frame)
    NSColor(white: dark ? 1 : 0, alpha: 0.18).setStroke()
    shape.lineWidth = 1
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()

    try out.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("✓ \(name)")
}

for (tab, name) in [(SettingsTab.clicks, "clicks"), (.movement, "movement"), (.about, "about")] {
    try render(tab, dark: false, to: "\(name)-light.png")
    try render(tab, dark: true, to: "\(name)-dark.png")
}
