import Cocoa

let outIconset = "/Users/pascal/.gemini/antigravity/scratch/Schedule/Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outIconset)
try fm.createDirectory(atPath: outIconset, withIntermediateDirectories: true)

func fillLinearGradient(ctx: CGContext, path: CGPath, bounds: CGRect, top: NSColor, bottom: NSColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [top.cgColor, bottom.cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: bounds.midX, y: bounds.maxY),
        end: CGPoint(x: bounds.midX, y: bounds.minY),
        options: []
    )
    ctx.restoreGState()
}

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let inset = s * 0.095
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Creator Studio Dark Mode Charcoal Squircle (#2C2C2E -> #1C1C1E)
    fillLinearGradient(
        ctx: ctx,
        path: squircle,
        bounds: rect,
        top: NSColor(calibratedRed: 0.173, green: 0.173, blue: 0.180, alpha: 1.0),
        bottom: NSColor(calibratedRed: 0.110, green: 0.110, blue: 0.118, alpha: 1.0)
    )

    // Subtle 1px inner rim
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(max(1.0, s * 0.005))
    ctx.strokePath()
    ctx.restoreGState()

    // Luminous Cobalt / Royal Blue cascading bars + milestone diamond
    let w = rect.width
    let barH = w * 0.125
    let barR = barH * 0.5
    let leftX = rect.minX + w * 0.16

    let bar1 = CGRect(x: leftX, y: rect.minY + w * 0.65, width: w * 0.38, height: barH)
    let bar2 = CGRect(x: leftX + w * 0.13, y: rect.minY + w * 0.45, width: w * 0.42, height: barH)
    let bar3 = CGRect(x: leftX + w * 0.25, y: rect.minY + w * 0.25, width: w * 0.28, height: barH)

    let topColor = NSColor(calibratedRed: 1.00, green: 0.56, blue: 0.52, alpha: 1.0)    // #FF8F85
    let midColor = NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.35, alpha: 1.0)    // #F26159
    let botColor = NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.24, alpha: 1.0)    // #D9403D

    for (idx, b) in [bar1, bar2, bar3].enumerated() {
        let p = CGPath(roundedRect: b, cornerWidth: barR, cornerHeight: barR, transform: nil)
        let t = idx == 0 ? topColor : midColor
        let bt = idx == 2 ? botColor : midColor
        fillLinearGradient(ctx: ctx, path: p, bounds: b, top: t, bottom: bt)

        ctx.saveGState()
        ctx.addPath(p)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(max(0.75, s * 0.003))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Milestone diamond (#93C5FD -> #3B82F6)
    let dCenter = CGPoint(x: bar3.maxX + w * 0.11, y: bar3.midY)
    let dRadius = barH * 0.68
    let diamond = CGMutablePath()
    diamond.move(to: CGPoint(x: dCenter.x, y: dCenter.y + dRadius))
    diamond.addLine(to: CGPoint(x: dCenter.x + dRadius, y: dCenter.y))
    diamond.addLine(to: CGPoint(x: dCenter.x, y: dCenter.y - dRadius))
    diamond.addLine(to: CGPoint(x: dCenter.x - dRadius, y: dCenter.y))
    diamond.closeSubpath()

    fillLinearGradient(
        ctx: ctx,
        path: diamond,
        bounds: diamond.boundingBox,
        top: NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.68, alpha: 1.0),    // #FFB8AD
        bottom: NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.35, alpha: 1.0)  // #F26159
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    if let png = renderIcon(size: px) {
        try png.write(to: URL(fileURLWithPath: "\(outIconset)/\(filename)"))
    }
}

print("Generated Cobalt Creator Studio iconset")
