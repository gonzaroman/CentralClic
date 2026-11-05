// Draws the app icon (a Magic Mouse with the middle zone highlighted) into an .iconset folder.
import AppKit

let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.45, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.50, green: 0.27, blue: 0.86, alpha: 1)])!.draw(in: bg, angle: -90)

    let mw = rect.width * 0.38, mh = rect.height * 0.66
    let m = NSRect(x: rect.midX - mw / 2, y: rect.midY - mh / 2, width: mw, height: mh)
    let mouse = NSBezierPath(roundedRect: m, xRadius: mw / 2, yRadius: mw / 2)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    NSColor.white.setFill()
    mouse.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    mouse.addClip()
    NSColor(srgbRed: 1.0, green: 0.62, blue: 0.12, alpha: 1).setFill()
    NSRect(x: m.minX + mw / 3, y: m.midY - mh * 0.05, width: mw / 3, height: mh * 0.55).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
