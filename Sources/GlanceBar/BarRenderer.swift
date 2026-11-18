import AppKit
import CoreText
import GlanceCore

/// Draws a `BarContent` with Core Graphics and Core Text. The menu bar view
/// and the snapshot renderer share it. Text is laid out once per distinct
/// string and kept, so a tick whose numbers did not change lays out nothing.
@MainActor
enum BarRenderer {
    static let sidePadding: CGFloat = 4
    static let itemGap: CGFloat = 7
    static let boxHeight: CGFloat = 15
    static let labelWidth: CGFloat = 6
    static let labelGap: CGFloat = 1.5
    static let barWidth: CGFloat = 2
    static let barPitch: CGFloat = 3
    static let boxInset: CGFloat = 2.5
    static let graphWidth = boxInset * 2 + CGFloat(BarContent.graphBars) * barPitch - (barPitch - barWidth)
    static let gaugeWidth: CGFloat = 8
    static let arrowWidth: CGFloat = 8
    /// One step of a graph or gauge, in points.
    static let step: CGFloat = 0.5

    enum Role: Hashable { case label, value, rate }

    private struct Key: Hashable {
        var text: String
        var role: Role
    }

    private static let fonts: [Role: NSFont] = [
        .label: .systemFont(ofSize: 6, weight: .bold),
        .value: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .rate: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
    ]
    private static var lines: [Key: (line: CTLine, width: CGFloat)] = [:]

    private static func line(_ text: String, _ role: Role) -> (line: CTLine, width: CGFloat) {
        let key = Key(text: text, role: role)
        if let known = lines[key] { return known }
        if lines.count > 400 { lines.removeAll(keepingCapacity: true) }
        // The color comes from the context at draw time, so one line serves every appearance and level.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: fonts[role]!,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let made = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        lines[key] = made
        return made
    }

    private static func width(of item: BarItem) -> CGFloat {
        switch item {
        case .graph: labelWidth + labelGap + graphWidth
        case .gauge: labelWidth + labelGap + gaugeWidth
        case .text(_, let template, _): line(template, .value).width.rounded(.up)
        case .rates: arrowWidth + line(BarContent.ratesTemplate, .rate).width.rounded(.up)
        }
    }

    /// The width the status item needs for this content.
    static func width(of content: BarContent) -> CGFloat {
        guard !content.items.isEmpty else { return 24 }
        let items = content.items.reduce(0) { $0 + width(of: $1) }
        return (sidePadding * 2 + items + itemGap * CGFloat(content.items.count - 1)).rounded(.up)
    }

    private static func color(_ level: Level, ink: NSColor) -> CGColor {
        switch level {
        case .normal: ink.cgColor
        case .high: NSColor.systemOrange.cgColor
        case .critical: NSColor.systemRed.cgColor
        }
    }

    /// Draws into a context whose origin is bottom left. Colors follow the current drawing appearance.
    static func draw(_ content: BarContent, height: CGFloat, in context: CGContext) {
        let ink = NSColor.labelColor
        let frame = ink.withAlphaComponent(0.5).cgColor
        let boxY = (((height - boxHeight) / 2) * 2).rounded() / 2
        guard !content.items.isEmpty else {
            draw("–", .value, x: sidePadding, baseline: boxY + 3, color: frame, in: context)
            return
        }
        var x = sidePadding
        for item in content.items {
            let itemWidth = width(of: item)
            switch item {
            case .graph(let label, let bars, let levels):
                drawLabel(label, x: x, boxY: boxY, color: ink.withAlphaComponent(0.9).cgColor, in: context)
                let boxX = x + labelWidth + labelGap
                strokeBox(CGRect(x: boxX, y: boxY, width: graphWidth, height: boxHeight), color: frame, in: context)
                for (index, steps) in bars.enumerated() where steps > 0 {
                    context.setFillColor(color(levels[index], ink: ink))
                    fill(CGRect(x: boxX + boxInset + CGFloat(index) * barPitch, y: boxY + 2, width: barWidth,
                                height: CGFloat(steps) * step), in: context)
                }
            case .gauge(let label, let steps, let level):
                drawLabel(label, x: x, boxY: boxY, color: ink.withAlphaComponent(0.9).cgColor, in: context)
                let boxX = x + labelWidth + labelGap
                strokeBox(CGRect(x: boxX, y: boxY, width: gaugeWidth, height: boxHeight), color: frame, in: context)
                if steps > 0 {
                    context.setFillColor(color(level, ink: ink))
                    fill(CGRect(x: boxX + 2, y: boxY + 2, width: gaugeWidth - 4, height: CGFloat(steps) * step),
                         in: context)
                }
            case .text(let text, _, let level):
                let made = line(text, .value)
                let baseline = (((height - fonts[.value]!.capHeight) / 2) * 2).rounded() / 2
                draw(made.line, x: x + itemWidth - made.width, baseline: baseline, color: color(level, ink: ink),
                     in: context)
            case .rates(let up, let down):
                let capHeight = fonts[.rate]!.capHeight
                let rows = [("↑", up, boxY + boxHeight - capHeight), ("↓", down, boxY)]
                for (arrow, text, baseline) in rows {
                    draw(arrow, .rate, x: x, baseline: baseline, color: ink.withAlphaComponent(0.6).cgColor,
                         in: context)
                    let made = line(text, .rate)
                    draw(made.line, x: x + itemWidth - made.width, baseline: baseline, color: ink.cgColor,
                         in: context)
                }
            }
            x += itemWidth + itemGap
        }
    }

    /// Three letters stacked beside a box, top to bottom.
    private static func drawLabel(_ label: String, x: CGFloat, boxY: CGFloat, color: CGColor, in context: CGContext) {
        let pitch = (boxHeight - fonts[.label]!.capHeight) / 2
        for (index, character) in label.prefix(3).enumerated() {
            let made = line(String(character), .label)
            draw(made.line, x: x + (labelWidth - made.width) / 2, baseline: boxY + CGFloat(2 - index) * pitch,
                 color: color, in: context)
        }
    }

    private static func draw(_ text: String, _ role: Role, x: CGFloat, baseline: CGFloat, color: CGColor,
                             in context: CGContext) {
        draw(line(text, role).line, x: x, baseline: baseline, color: color, in: context)
    }

    private static func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat, color: CGColor, in context: CGContext) {
        context.setFillColor(color)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
    }

    private static func strokeBox(_ rect: CGRect, color: CGColor, in context: CGContext) {
        context.setStrokeColor(color)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 2.5, cornerHeight: 2.5,
                               transform: nil))
        context.strokePath()
    }

    /// Fills on whole device pixels, so half-point steps stay sharp on a Retina display and never
    /// vanish on a standard one.
    private static func fill(_ rect: CGRect, in context: CGContext) {
        var device = context.convertToDeviceSpace(rect).standardized
        let top = (device.maxY).rounded(), right = device.maxX.rounded()
        device.origin = CGPoint(x: device.minX.rounded(), y: device.minY.rounded())
        device.size = CGSize(width: max(1, right - device.minX), height: max(1, top - device.minY))
        context.fill(context.convertToUserSpace(device))
    }
}

/// The menu bar item's drawing surface: a subview of the status button that redraws only when its
/// content changes.
///
/// AppKit asks for the same content several times per change: once for the menu bar, and again for
/// the copy of the item it keeps on every other display, each in that display's appearance and
/// scale. Every distinct rendering is drawn once and copied from then on.
final class BarView: NSView {
    private struct Rendering: Hashable {
        var appearance: NSAppearance.Name
        var scale: CGFloat
        var size: CGSize
    }

    var content = BarContent(items: []) {
        didSet {
            guard content != oldValue else { return }
            rendered.removeAll(keepingCapacity: true)
            needsDisplay = true
        }
    }
    private var rendered: [Rendering: CGImage] = [:]

    /// Clicks belong to the status button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = context.convertToDeviceSpace(CGSize(width: 1, height: 1)).width.magnitude
        let key = Rendering(appearance: NSAppearance.currentDrawing().name, scale: scale, size: bounds.size)
        guard let image = rendered[key] ?? render(key) else {
            BarRenderer.draw(content, height: bounds.height, in: context)
            return
        }
        rendered[key] = image
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    /// Draws the content into a bitmap at the pixel size of the asking context.
    private func render(_ key: Rendering) -> CGImage? {
        let width = Int((key.size.width * key.scale).rounded(.up))
        let height = Int((key.size.height * key.scale).rounded(.up))
        guard width > 0, height > 0, key.scale > 0,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        bitmap.scaleBy(x: key.scale, y: key.scale)
        BarRenderer.draw(content, height: key.size.height, in: bitmap)
        return bitmap.makeImage()
    }
}
