// Draws the HostKeeper app icon and writes Resources/AppIcon.icns plus docs/logo.png.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(in ctx: CGContext) {
    // Body: the standard macOS icon grid leaves ~100pt of padding around an 824pt rounded square.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1E1B4B))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x312E81), color(0x0E7490), color(0x14B8A6)] as CFArray,
        locations: [0, 0.6, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    ctx.restoreGState()

    // Terminal window
    let window = CGRect(x: 205, y: 300, width: 614, height: 470)
    let windowPath = CGPath(roundedRect: window, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.4))
    ctx.addPath(windowPath)
    ctx.setFillColor(color(0x0B1220, 0.92))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(windowPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // Title bar dots
    for (i, hex) in [UInt32(0xF87171), 0xFBBF24, 0x34D399].enumerated() {
        ctx.setFillColor(color(hex))
        ctx.fillEllipse(in: CGRect(x: 250 + CGFloat(i) * 52, y: 700, width: 30, height: 30))
    }

    // Prompt: ">" and "_"
    ctx.setStrokeColor(color(0x5EEAD4))
    ctx.setLineWidth(44)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 290, y: 610))
    ctx.addLine(to: CGPoint(x: 395, y: 530))
    ctx.addLine(to: CGPoint(x: 290, y: 450))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 445, y: 440))
    ctx.addLine(to: CGPoint(x: 525, y: 440))
    ctx.strokePath()

    // Key, angled across the lower right corner of the window
    ctx.saveGState()
    ctx.translateBy(x: 625, y: 375)
    ctx.rotate(by: -.pi / 4)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.45))
    let key = CGMutablePath()
    key.addEllipse(in: CGRect(x: -88, y: -88, width: 176, height: 176))
    key.addRoundedRect(in: CGRect(x: 70, y: -24, width: 210, height: 48), cornerWidth: 14, cornerHeight: 14)
    key.addRect(CGRect(x: 200, y: -78, width: 32, height: 64))
    key.addRect(CGRect(x: 248, y: -64, width: 30, height: 50))
    ctx.addPath(key)
    ctx.setFillColor(color(0xFBBF24))
    ctx.fillPath()
    ctx.restoreGState()

    // Key hole and highlight drawn without the shadow
    ctx.saveGState()
    ctx.translateBy(x: 625, y: 375)
    ctx.rotate(by: -.pi / 4)
    ctx.setFillColor(color(0x0B1220))
    ctx.fillEllipse(in: CGRect(x: -35, y: -35, width: 70, height: 70))
    ctx.setStrokeColor(color(0xFDE68A))
    ctx.setLineWidth(10)
    ctx.addArc(center: .zero, radius: 66, startAngle: .pi * 0.6, endAngle: .pi * 1.1, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(at: URL(filePath: "Resources"), withIntermediateDirectories: true)
try fm.createDirectory(at: URL(filePath: "docs"), withIntermediateDirectories: true)
try render(size: 512).write(to: URL(filePath: "docs/logo.png"))

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/logo.png" : "iconutil failed")
