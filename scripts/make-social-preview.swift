// Draws docs/social-preview.png (1280×640), the image shown when the repository link is shared.
// Upload it in GitHub → Settings → General → Social preview.
//   swiftc scripts/make-social-preview.swift -o /tmp/social && /tmp/social .
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let docs = root.appendingPathComponent("docs")
let width = 1280, height = 640

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

// Background: the icon's blue → purple gradient, a bit deeper so white text stands out.
NSGradient(colors: [NSColor(srgbRed: 0.22, green: 0.32, blue: 0.90, alpha: 1),
                    NSColor(srgbRed: 0.42, green: 0.20, blue: 0.78, alpha: 1)])!.draw(in: canvas, angle: -35)

// Right: the real settings window.
if let shot = NSImage(contentsOf: docs.appendingPathComponent("screenshots/clicks-dark.png")) {
    let h: CGFloat = 640
    let w = h * shot.size.width / shot.size.height
    shot.draw(in: NSRect(x: CGFloat(width) - w + 10, y: (CGFloat(height) - h) / 2, width: w, height: h))
}

// Left: icon, name, tagline and highlights.
let left: CGFloat = 76
if let icon = NSImage(contentsOf: docs.appendingPathComponent("icon.png")) {
    icon.draw(in: NSRect(x: left - 18, y: 400, width: 170, height: 170))
}
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1, at y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    NSAttributedString(string: s, attributes: attributes).draw(at: NSPoint(x: left, y: y))
}
text("Magic Middle Click", size: 60, weight: .heavy, at: 304)
text("The missing middle button", size: 36, weight: .semibold, alpha: 0.95, at: 248)
text("for the Apple Magic Mouse", size: 36, weight: .semibold, alpha: 0.95, at: 200)
text("Adjustable click zones · Pointer speed", size: 24, weight: .regular, alpha: 0.85, at: 140)
text("No acceleration · Scroll speed & direction", size: 24, weight: .regular, alpha: 0.85, at: 108)
text("Free · macOS 13+ · github.com/gonzaroman/magic-middle-click", size: 20, weight: .medium, alpha: 0.75, at: 56)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: docs.appendingPathComponent("social-preview.png"))
print("✓ docs/social-preview.png")
