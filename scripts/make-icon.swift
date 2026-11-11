// Renders the app icon (original artwork) to Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824×824 body centred on a 1024 canvas, continuous-corner squircle.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(shape); ctx.setFillColor(color(0x1C1D22)); ctx.fillPath()
    ctx.restoreGState()

    // Graphite gradient background.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x34363E), color(0x15161A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Subtle top sheen.
    let sheen = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
    ctx.restoreGState()

    // Storage ring: segments in a colourist palette, small gaps between them.
    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 248, width: CGFloat = 104
    let segments: [(CGFloat, UInt32)] = [(0.38, 0x2EC4B6), (0.24, 0xFF9F1C), (0.16, 0xE5487F), (0.12, 0x4D8DFF)]
    var start = CGFloat.pi / 2
    let gap: CGFloat = 0.06
    ctx.setLineWidth(width)
    ctx.setLineCap(.butt)
    // Empty track for the remaining (free) space.
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    for (fraction, hex) in segments {
        let sweep = fraction * 2 * .pi
        ctx.setStrokeColor(color(hex))
        ctx.addArc(center: center, radius: radius, startAngle: start - gap / 2, endAngle: start - sweep + gap / 2, clockwise: true)
        ctx.strokePath()
        start -= sweep
    }

    // Centre: a colour-wheel "puck" — white dot with a soft ring.
    ctx.setFillColor(color(0xFFFFFF, 0.10))
    ctx.fillEllipse(in: CGRect(x: 512 - 120, y: 512 - 120, width: 240, height: 240))
    ctx.setFillColor(color(0xF4F4F6))
    ctx.fillEllipse(in: CGRect(x: 512 - 46, y: 512 - 46, width: 92, height: 92))

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: fm.temporaryDirectory.path).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns written" : "iconutil failed")
