import GlanceCore
import SwiftUI

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x8e8e93
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}

enum Palette {
    static let ok = Color(hex: "#30d158")
    static let amber = Color(hex: "#ff9f0a")
    static let red = Color(hex: "#ff453a")

    static let cpu = Color(hex: "#0a84ff")
    static let gpu = Color(hex: "#bf5af2")
    static let memory = Color(hex: "#30d1b2")
    static let wired = Color(hex: "#0a84ff")
    static let compressed = Color(hex: "#bf5af2")
    static let disk = Color(hex: "#5e5ce6")
    static let download = Color(hex: "#0a84ff")
    static let upload = Color(hex: "#ff6482")

    /// A meter keeps its own color until its reading turns worrying.
    static func level(_ level: Level, normal: Color) -> Color {
        switch level {
        case .normal: normal
        case .high: amber
        case .critical: red
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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

    init(used: Double, color: Color) {
        parts = [(used, color)]
    }

    init(parts: [(share: Double, color: Color)]) {
        self.parts = parts
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                HStack(spacing: parts.count > 1 ? 1 : 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.share > 0 {
                            Rectangle().fill(part.color.gradient)
                                .frame(width: max(2, geometry.size.width * min(1, part.share)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var color: Color = .primary
    var detail: String?

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
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    func sectionTitle() -> some View {
        font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    func caption() -> some View {
        font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
    }
}

/// The last readings as bars, newest on the right, each colored by its own level.
struct HistoryChart: View {
    /// Shares of the full height, oldest first.
    var values: [Float]
    var slots: Int
    var color: Color

    var body: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(slots)
            let width = max(1, pitch - 1.5)
            let empty = slots - values.count
            for slot in 0..<slots {
                let x = CGFloat(slot) * pitch
                let track = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: track, cornerRadius: 1.5), with: .color(.primary.opacity(0.06)))
                guard slot >= empty else { continue }
                let value = Double(values[slot - empty])
                let height = max(1.5, size.height * CGFloat(min(1, value)))
                let bar = CGRect(x: x, y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.5),
                             with: .color(Palette.level(Levels.load(value), normal: color)))
            }
        }
    }
}

/// One vertical bar per core, efficiency cores first.
struct CoreBars: View {
    var cores: [Double]
    var efficiency: Int

    var body: some View {
        HStack(spacing: 3) {
            if efficiency > 0, efficiency < cores.count {
                group("E", cores.prefix(efficiency))
                Spacer().frame(width: 5)
                group("P", cores.dropFirst(efficiency))
            } else {
                group(nil, cores[...])
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func group(_ name: String?, _ loads: ArraySlice<Double>) -> some View {
        if let name {
            Text(name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.primary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Palette.level(Levels.load(load), normal: Palette.cpu).gradient)
                        .frame(height: max(2, geometry.size.height * min(1, load)))
                }
            }
        }
    }
}

/// Download above the middle line, upload below, each scaled to its own peak.
struct NetworkChart: View {
    var down: [Float]
    var up: [Float]
    var slots: Int

    var body: some View {
        Canvas { context, size in
            let pitch = size.width / CGFloat(slots)
            let width = max(1, pitch - 1.5)
            let half = ((size.height - 1) / 2).rounded(.down)
            context.fill(Path(CGRect(x: 0, y: half, width: size.width, height: 1)),
                         with: .color(.primary.opacity(0.12)))
            // Below 10 KB/s a chart stays flat instead of magnifying idle chatter.
            let downScale = max(down.max() ?? 0, 10_000), upScale = max(up.max() ?? 0, 10_000)
            for (index, value) in down.enumerated() {
                let height = max(1, half * CGFloat(value / downScale))
                let bar = CGRect(x: CGFloat(index + slots - down.count) * pitch, y: half - height, width: width,
                                 height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(Palette.download))
            }
            for (index, value) in up.enumerated() {
                let height = max(1, half * CGFloat(value / upScale))
                let bar = CGRect(x: CGFloat(index + slots - up.count) * pitch, y: half + 1, width: width,
                                 height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(Palette.upload))
            }
        }
    }
}
