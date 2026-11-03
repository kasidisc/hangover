// Draws Resources/AppIcon.icns: a two-tone capsule on a soft blue-to-teal rounded square. Original artwork.
// Run: swiftc scripts/make-icon/main.swift -o .build/make-icon && .build/make-icon
import AppKit

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(colors: [NSColor(red: 0.32, green: 0.55, blue: 0.98, alpha: 1),
                        NSColor(red: 0.27, green: 0.82, blue: 0.78, alpha: 1)])!.draw(in: bg, angle: -60)

    // Capsule, rotated 45°, left half white, right half warm coral.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: s / 2, y: s / 2)
    ctx.rotate(by: .pi / 4)
    let w = s * 0.58, h = s * 0.24
    let capsule = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.white.setFill()
    capsule.fill()
    NSGraphicsContext.restoreGraphicsState()
    capsule.addClip()
    NSColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1).setFill()
    NSRect(x: 0, y: -h / 2, width: w / 2, height: h).fill()
    NSColor.black.withAlphaComponent(0.08).setStroke()
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 0, y: -h / 2)); seam.line(to: NSPoint(x: 0, y: h / 2))
    seam.lineWidth = max(1, s * 0.006)
    seam.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: ".build/AppIcon.iconset")
try? fm.removeItem(at: set)
try fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try draw(size: base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
