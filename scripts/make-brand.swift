// Draws the README banner and the social preview image from the app icon.
// Run: swift scripts/make-brand.swift
// Writes docs/banner.png (1600 x 440, shown 800 wide) and docs/social-preview.png (1280 x 640).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let name = "Glance Bar"
let tagline = "System stats at a glance in your menu bar"
let amber = color("#ff9f0a")
let glows = [color("#0a84ff"), color("#bf5af2")]
/// Bar heights of the decoration, 0 to 1: a CPU history as the menu bar item draws it.
let levels: [CGFloat] = [0.18, 0.24, 0.2, 0.3, 0.26, 0.42, 0.36, 0.3, 0.52, 0.7, 0.94, 0.88, 0.6, 0.44, 0.5, 0.38,
                         0.3, 0.34, 0.26, 0.22, 0.3, 0.46, 0.4, 0.28]

func color(_ hex: String) -> NSColor {
    let v = UInt64(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ string: String, _ font: NSFont, alpha: CGFloat = 1, tracking: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: alpha),
                                                    .kern: tracking])
}

/// The app icon without the transparent margin the icon grid leaves around the tile.
func drawIcon(_ icon: NSImage, in rect: NSRect) {
    let margin = rect.width * 0.1 / 0.8
    icon.draw(in: rect.insetBy(dx: -margin, dy: -margin))
}

/// A history graph on its track, white with amber where the load ran high, as in the menu bar.
func drawGraph(in rect: NSRect, bar: CGFloat, gap: CGFloat) {
    for (index, level) in levels.enumerated() {
        let x = rect.minX + CGFloat(index) * (bar + gap)
        NSColor(white: 1, alpha: 0.07).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY, width: bar, height: rect.height), xRadius: bar * 0.3,
                     yRadius: bar * 0.3).fill()
        (level > 0.85 ? amber : NSColor(white: 1, alpha: 0.92)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY, width: bar, height: rect.height * level),
                     xRadius: bar * 0.3, yRadius: bar * 0.3).fill()
    }
}

func graphWidth(bar: CGFloat, gap: CGFloat) -> CGFloat {
    bar * CGFloat(levels.count) + gap * CGFloat(levels.count - 1)
}

func canvas(_ width: Int, _ height: Int, radius: CGFloat, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    let inset: CGFloat = radius > 0 ? 1 : 0  // room for the border of the rounded card
    let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1))!.draw(in: shape, angle: -70)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // Two soft glows in the panel's colors, so the card is not a flat grey.
    for (glow, center) in [(glows[0], NSPoint(x: bounds.width * 0.08, y: bounds.height * 1.05)),
                           (glows[1], NSPoint(x: bounds.width * 0.98, y: -bounds.height * 0.1))] {
        NSGradient(starting: glow.withAlphaComponent(0.22), ending: glow.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: bounds.width * 0.42, options: [])
    }
    NSGraphicsContext.restoreGraphicsState()
    if radius > 0 {
        NSColor(white: 1, alpha: 0.1).setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }
    draw(bounds)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")) else {
    print("Resources/AppIcon.icns is missing: run swift scripts/make-icon.swift first")
    exit(1)
}

// README banner: icon, name and tagline on the left, the history graph on the right.
let banner = canvas(1600, 440, radius: 44) { bounds in
    let tile: CGFloat = 196
    drawIcon(icon, in: NSRect(x: 96, y: bounds.midY - tile / 2, width: tile, height: tile))
    let title = text(name, rounded(104, .bold), tracking: -1)
    let sub = text(tagline, rounded(35, .medium), alpha: 0.62)
    let left = 96 + tile + 56
    let block = title.size().height + sub.size().height - 6
    title.draw(at: NSPoint(x: left, y: bounds.midY + block / 2 - title.size().height))
    sub.draw(at: NSPoint(x: left + 4, y: bounds.midY - block / 2))
    let width = graphWidth(bar: 11, gap: 5)
    drawGraph(in: NSRect(x: bounds.maxX - 96 - width, y: bounds.midY - 70, width: width, height: 140), bar: 11, gap: 5)
}

// Social preview: the same parts stacked and centered, with no transparent corners.
let social = canvas(1280, 640, radius: 0) { bounds in
    let tile: CGFloat = 176
    let title = text(name, rounded(96, .bold), tracking: -1)
    let sub = text(tagline, rounded(34, .medium), alpha: 0.62)
    let width = graphWidth(bar: 14, gap: 6)
    let graph: CGFloat = 96
    var y = bounds.midY + (tile + 22 + title.size().height + sub.size().height + 44 + graph) / 2
    y -= tile
    drawIcon(icon, in: NSRect(x: bounds.midX - tile / 2, y: y, width: tile, height: tile))
    y -= 22 + title.size().height
    title.draw(at: NSPoint(x: bounds.midX - title.size().width / 2, y: y))
    y -= sub.size().height
    sub.draw(at: NSPoint(x: bounds.midX - sub.size().width / 2, y: y))
    y -= 44 + graph
    drawGraph(in: NSRect(x: bounds.midX - width / 2, y: y, width: width, height: graph), bar: 14, gap: 6)
}

for (rep, file) in [(banner, "docs/banner.png"), (social, "docs/social-preview.png")] {
    let url = root.appendingPathComponent(file)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("Wrote \(url.path)")
}
