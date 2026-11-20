// Draws the app icon (a menu bar history graph on a dark squircle) and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

let levels: [CGFloat] = [0.22, 0.34, 0.28, 0.5, 0.92, 0.62, 0.4, 0.3]
let amber = NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1)

func icon(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(white: 0.2, alpha: 1),
               ending: NSColor(white: 0.07, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    shape.lineWidth = s * 0.004
    shape.stroke()

    // The graph box, as in the menu bar.
    let box = NSRect(x: tile.minX + tile.width * 0.16, y: tile.minY + tile.height * 0.27, width: tile.width * 0.68,
                     height: tile.height * 0.46)
    let frame = NSBezierPath(roundedRect: box, xRadius: box.height * 0.16, yRadius: box.height * 0.16)
    frame.lineWidth = max(1, tile.width * 0.022)
    NSColor(white: 1, alpha: 0.55).setStroke()
    frame.stroke()

    let pad = box.height * 0.16
    let gap = box.width * 0.03
    let room = box.width - pad * 2
    let barWidth = (room - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
    for (index, level) in levels.enumerated() {
        let bar = NSRect(x: box.minX + pad + CGFloat(index) * (barWidth + gap), y: box.minY + pad, width: barWidth,
                         height: (box.height - pad * 2) * level)
        let color = level > 0.85 ? amber : NSColor.white
        NSGradient(starting: color, ending: color.withAlphaComponent(0.82))!
            .draw(in: NSBezierPath(roundedRect: bar, xRadius: barWidth * 0.2, yRadius: barWidth * 0.2), angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! icon(size * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(task.terminationStatus)
}
print("Wrote \(output.path)")
