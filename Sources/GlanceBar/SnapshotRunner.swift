import AppKit
import GlanceCore
import SwiftUI

/// `GlanceBar --snapshot <dir>`: take readings (live ones, or made-up ones with `--demo`), then
/// render the menu bar item and both panel screens to PNG. Used to check layouts and to make
/// README images without clicking through the menu bar.
@MainActor
enum SnapshotRunner {
    static func run(into directory: URL, demo: Bool) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let monitor = Monitor(demo: demo)
        if !demo { await monitor.prime() }

        let content = BarContent.make(snapshot: monitor.snapshot,
                                      cpuHistory: monitor.cpuHistory.suffix(BarContent.graphBars),
                                      visible: monitor.settings.visible)
        writeBar(content, dark: true, to: directory.appendingPathComponent("menubar.png"))
        writeBar(content, dark: false, to: directory.appendingPathComponent("menubar-light.png"))

        let panel = PanelModel(monitor: monitor)
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            panel.showingSettings = false
            await render(panel, scheme: scheme, to: directory.appendingPathComponent("panel-\(suffix).png"))
            panel.showingSettings = true
            await render(panel, scheme: scheme, to: directory.appendingPathComponent("settings-\(suffix).png"))
        }

        let snapshot = monitor.snapshot
        print("Rendered snapshots to \(directory.path)")
        print("CPU \(snapshot.cpu.map { Format.percent($0.total) } ?? "-")"
            + ", GPU \(snapshot.gpu.map(Format.percent) ?? "-")"
            + ", memory \(snapshot.memory.map { Format.percent($0.usedFraction) } ?? "-")"
            + ", temperature \(snapshot.temperature.map { Format.degrees($0.average) } ?? "-")"
            + ", battery \(snapshot.battery.map { "\($0.percent)%" } ?? "-")"
            + ", disk \(snapshot.disk.map { Format.percent($0.usedFraction) } ?? "-")"
            + ", network up \(snapshot.network.map { Format.rate($0.up) } ?? "-")"
            + " down \(snapshot.network.map { Format.rate($0.down) } ?? "-")")
    }

    /// The menu bar item on a strip the color of the menu bar, enlarged four times.
    private static func writeBar(_ content: BarContent, dark: Bool, to url: URL) {
        let pad: CGFloat = 8, height: CGFloat = 24, scale: CGFloat = 4
        let width = BarRenderer.width(of: content) + pad * 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                         pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let graphics = context.cgContext
            graphics.scaleBy(x: scale, y: scale)
            graphics.setFillColor(NSColor(white: dark ? 0.17 : 0.93, alpha: 1).cgColor)
            graphics.fill(CGRect(x: 0, y: 0, width: width, height: height))
            graphics.translateBy(x: pad, y: 0)
            BarRenderer.draw(content, height: height, in: graphics)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Draws the panel in a window that never comes on screen. A window, unlike `ImageRenderer`,
    /// also draws the AppKit-backed controls (segmented pickers, switches).
    private static func render(_ panel: PanelModel, scheme: ColorScheme, to url: URL) async {
        let view = PanelView()
            .environment(panel)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        // Canvases and pickers finish laying out a moment after they join a window.
        try? await Task.sleep(for: .milliseconds(150))
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bounds = hosting.bounds, scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        window.close()
        try? rounded(rep, radius: 14 * scale)?.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The image with the popover's rounded corners, transparent outside them.
    private static func rounded(_ source: NSBitmapImageRep, radius: CGFloat) -> NSBitmapImageRep? {
        guard let image = source.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage().map { NSBitmapImageRep(cgImage: $0) }
    }
}
