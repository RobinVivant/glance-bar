import GlanceCore
import SwiftUI

enum Palette {
    static let ok = Color(nsColor: .systemGreen)
    static let amber = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)

    static let cpu = Color(nsColor: .systemBlue)
    static let gpu = Color(nsColor: .systemPurple)
    static let memory = Color(nsColor: .systemTeal)
    static let wired = Color(nsColor: .systemBlue)
    static let compressed = Color(nsColor: .systemPurple)
    static let disk = Color(nsColor: .systemIndigo)
    static let download = Color(nsColor: .systemBlue)
    static let upload = Color(nsColor: .systemPink)

    /// A meter keeps its own color until its reading turns worrying.
    static func level(_ level: Level, normal: Color) -> Color {
        switch level {
        case .normal: normal
        case .high: amber
        case .critical: red
        }
    }
}

enum Surface {
    static let corner: CGFloat = 11

    /// The fill of a card or tile, a shade stronger under the pointer.
    static func fill(highlighted: Bool) -> Color {
        Color.primary.opacity(highlighted ? 0.12 : 0.055)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.fill(highlighted: highlighted),
                        in: RoundedRectangle(cornerRadius: Surface.corner, style: .continuous))
    }
}

struct Pill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// A slim capsule level bar, one or more colored parts on a shared track.
struct CapsuleBar: View {
    /// Each part's share of the whole, 0 to 1, drawn left to right.
    var parts: [(share: Double, color: Color)]
    /// The part under the pointer: the others fade while it is set.
    var highlight: Int?
    /// Called with a part's index as the pointer enters and leaves it.
    var onHover: ((Int, Bool) -> Void)?

    init(used: Double, color: Color) {
        parts = [(used, color)]
    }

    init(parts: [(share: Double, color: Color)], highlight: Int? = nil, onHover: ((Int, Bool) -> Void)? = nil) {
        self.parts = parts
        self.highlight = highlight
        self.onHover = onHover
    }

    var body: some View {
        GeometryReader { geometry in
            let visible = Array(parts.enumerated()).filter { $0.element.share > 0 }
            let gap: CGFloat = visible.count > 1 ? 1 : 0
            let widths = segmentWidths(for: visible.map(\.element.share), totalWidth: geometry.size.width, gap: gap)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                HStack(spacing: gap) {
                    ForEach(Array(zip(visible, widths)), id: \.0.offset) { item, width in
                        Rectangle().fill(item.element.color.gradient)
                            .frame(width: width)
                            .opacity(highlight == nil || highlight == item.offset ? 1 : Fade.others)
                    }
                }
            }
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                if let onHover {
                    // Extends 5 pt above and below the 6 pt track without overlapping adjacent segments.
                    HStack(spacing: gap) {
                        ForEach(Array(zip(visible, widths)), id: \.0.offset) { item, width in
                            Color.clear
                                .frame(width: width, height: 16)
                                .contentShape(Rectangle())
                                .onHover { onHover(item.offset, $0) }
                        }
                    }
                }
            }
        }
        .frame(height: 6)
    }

    private func segmentWidths(for shares: [Double], totalWidth: CGFloat, gap: CGFloat) -> [CGFloat] {
        guard !shares.isEmpty else { return [] }
        let available = max(0, totalWidth - gap * CGFloat(shares.count - 1))
        let raw = shares.map { max(2, available * CGFloat(min(1, $0))) }
        let sum = raw.reduce(0, +)
        guard sum > available, sum > 0 else { return raw }
        let scale = available / sum
        return raw.map { $0 * scale }
    }
}

enum Fade {
    /// What is not under the pointer steps back this far.
    static let others = 0.4
}

struct StatTile: View {
    var value: String
    var label: String
    var color: Color = .primary
    var detail: String?
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            if let detail {
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.fill(highlighted: highlighted),
                    in: RoundedRectangle(cornerRadius: Surface.corner, style: .continuous))
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        var configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
                .background(Color.primary.opacity(hovering ? 0.14 : 0.08),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// A soft backdrop that shows under the pointer. It is drawn outside the view's own frame, so
/// adding it moves nothing.
struct HoverBackdrop: ViewModifier {
    var outset: CGFloat
    var corner: CGFloat
    var enabled = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.primary.opacity(enabled && hovering ? 0.1 : 0))
                    .padding(-outset)
            }
            .onHover { hovering = $0 }
    }
}

extension View {
    func sectionTitle() -> some View {
        font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    func caption() -> some View {
        font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
    }

    func hoverBackdrop(outset: CGFloat = 4, corner: CGFloat = 5, enabled: Bool = true) -> some View {
        modifier(HoverBackdrop(outset: outset, corner: corner, enabled: enabled))
    }
}

/// The last readings as bars, newest on the right, each colored by its own level.
struct HistoryChart: View {
    /// Shares of the full height, oldest first.
    var values: [Float]
    var slots: Int
    var color: Color
    /// The column under the pointer: its track lights up and the other bars fade.
    var highlight: Int?
    /// Called with the column under the pointer, or nil once the pointer leaves the chart.
    var onProbe: ((Int?) -> Void)?

    var body: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(slots)
            let width = max(1, pitch - 1.5)
            let empty = slots - values.count
            for slot in 0..<slots {
                let x = CGFloat(slot) * pitch
                let track = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: track, cornerRadius: 1.5),
                             with: .color(.primary.opacity(slot == highlight ? 0.22 : 0.06)))
                guard slot >= empty else { continue }
                let value = Double(values[slot - empty])
                let height = max(1.5, size.height * CGFloat(min(1, value)))
                let bar = CGRect(x: x, y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.5),
                             with: .color(Palette.level(Levels.load(value), normal: color)
                                 .opacity(highlight == nil || highlight == slot ? 1 : Fade.others)))
            }
        }
        .probing(slots: slots, onProbe)
    }
}

/// Reports which of a chart's equal columns the pointer is over.
private struct ColumnProbe: ViewModifier {
    var slots: Int
    var onProbe: ((Int?) -> Void)?

    func body(content: Content) -> some View {
        if let onProbe {
            content.overlay {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                onProbe(ChartProbe.slot(at: point.x, width: geometry.size.width, slots: slots))
                            case .ended:
                                onProbe(nil)
                            }
                        }
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    func probing(slots: Int, _ onProbe: ((Int?) -> Void)?) -> some View {
        modifier(ColumnProbe(slots: slots, onProbe: onProbe))
    }
}

/// One vertical bar per core, efficiency cores first.
struct CoreBars: View {
    var cores: [Double]
    var efficiency: Int
    var placeholderCount = 0
    /// The core under the pointer: its track lights up and the other bars fade.
    var highlight: Int?
    /// Called with a core's index as the pointer enters and leaves its bar.
    var onHover: ((Int, Bool) -> Void)?

    var body: some View {
        let count = cores.isEmpty ? placeholderCount : cores.count
        HStack(spacing: 3) {
            if efficiency > 0, efficiency < count {
                group("E", 0..<efficiency)
                Spacer().frame(width: 5)
                group("P", efficiency..<count)
            } else {
                group(nil, 0..<count)
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func group(_ name: String?, _ range: Range<Int>) -> some View {
        if let name {
            Text(name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        ForEach(range, id: \.self) { index in
            let load = cores.indices.contains(index) ? cores[index] : nil
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.primary.opacity(highlight == index ? 0.24 : 0.1))
                    if let load {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Palette.level(Levels.load(load), normal: Palette.cpu).gradient)
                            .frame(height: max(2, geometry.size.height * min(1, load)))
                            .opacity(highlight == nil || highlight == index ? 1 : Fade.others)
                    }
                }
            }
            // Reaches halfway into the gap on each side, so moving along the row never falls between two bars.
            .contentShape(Rectangle().inset(by: -1.5))
            .onHover { inside in
                if cores.indices.contains(index) { onHover?(index, inside) }
            }
        }
    }
}

/// Download above the middle line, upload below, each scaled to its own peak.
struct NetworkChart: View {
    var down: [Float]
    var up: [Float]
    var slots: Int
    /// The column under the pointer: it gets a backdrop and the other bars fade.
    var highlight: Int?
    /// Called with the column under the pointer, or nil once the pointer leaves the chart.
    var onProbe: ((Int?) -> Void)?

    var body: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(slots)
            let width = max(1, pitch - 1.5)
            let half = ((size.height - 1) / 2).rounded(.down)
            if let highlight {
                let column = CGRect(x: CGFloat(highlight) * pitch, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: column, cornerRadius: 1.5), with: .color(.primary.opacity(0.16)))
            }
            context.fill(Path(CGRect(x: 0, y: half, width: size.width, height: 1)),
                         with: .color(.primary.opacity(0.12)))
            // Below 10 KB/s a chart stays flat instead of magnifying idle chatter.
            let downScale = max(down.max() ?? 0, 10_000), upScale = max(up.max() ?? 0, 10_000)
            for (index, value) in down.enumerated() {
                let slot = index + slots - down.count
                let height = max(1, half * CGFloat(value / downScale))
                let bar = CGRect(x: CGFloat(slot) * pitch, y: half - height, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1),
                             with: .color(Palette.download.opacity(faded(slot) ? Fade.others : 1)))
            }
            for (index, value) in up.enumerated() {
                let slot = index + slots - up.count
                let height = max(1, half * CGFloat(value / upScale))
                let bar = CGRect(x: CGFloat(slot) * pitch, y: half + 1, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1),
                             with: .color(Palette.upload.opacity(faded(slot) ? Fade.others : 1)))
            }
        }
        .probing(slots: slots, onProbe)
    }

    private func faded(_ slot: Int) -> Bool { highlight != nil && highlight != slot }
}
