/// Optional status glyph beside a menu bar text readout.
public enum BatteryGlyph: Equatable, Sendable {
    case none, bolt, plug
}

/// One element of the menu bar item, already reduced to what gets drawn.
public enum BarItem: Equatable, Sendable {
    /// A history graph: bar heights in steps, oldest first, with a level per bar.
    case graph(label: String, bars: [UInt8], levels: [Level])
    /// One level bar, its fill in steps.
    case gauge(label: String, fill: UInt8, level: Level)
    /// A value as text. `template` is the widest string of the same length, so the slot keeps its width.
    case text(String, template: String, level: Level, glyph: BatteryGlyph = .none)
    /// Upload over download.
    case rates(up: String, down: String)
}

/// The whole menu bar item. Heights are whole steps of half a point, one
/// pixel on a Retina display, so two contents are equal exactly when they
/// draw the same pixels and the view can skip the redraw.
public struct BarContent: Equatable, Sendable {
    public static let steps = 22
    public static let graphBars = 12
    public static let ratesTemplate = "999 MB/s"

    public var items: [BarItem]

    public init(items: [BarItem]) { self.items = items }

    public static func make(snapshot: Snapshot, cpuHistory: [Float], visible: [Meter],
                            temperatureUnit: TemperatureUnit = .celsius) -> BarContent {
        var items: [BarItem] = []
        for meter in visible {
            switch meter {
            case .cpu:
                let recent = cpuHistory.suffix(graphBars).map(Double.init)
                let padding = [Double?](repeating: nil, count: graphBars - recent.count)
                let values = padding + recent.map(Optional.some)
                items.append(.graph(label: meter.label, bars: values.map { $0.map { max(2, step($0)) } ?? 0 },
                                    levels: values.map { $0.map(Levels.load) ?? .normal }))
            case .gpu:
                guard let gpu = snapshot.gpu else { continue }
                items.append(.gauge(label: meter.label, fill: step(gpu), level: Levels.load(gpu)))
            case .memory:
                guard let memory = snapshot.memory else { continue }
                items.append(.gauge(label: meter.label, fill: step(memory.pressureFraction),
                                    level: memory.pressure))
            case .disk:
                guard let disk = snapshot.disk else { continue }
                items.append(.gauge(label: meter.label, fill: step(disk.usedFraction),
                                    level: Levels.disk(disk.usedFraction)))
            case .temperature:
                guard let temperature = snapshot.temperature else { continue }
                let text = Format.degrees(temperature.average, unit: temperatureUnit)
                items.append(.text(text, template: text.count > 3 ? "888°" : "88°",
                                   level: Levels.temperature(temperature.average)))
            case .battery:
                guard let battery = snapshot.battery else { continue }
                let text = "\(battery.percent)%"
                let glyph: BatteryGlyph = battery.charging ? .bolt : (battery.onAC ? .plug : .none)
                items.append(.text(text, template: text.count > 3 ? "100%" : "88%",
                                   level: Levels.battery(battery), glyph: glyph))
            case .network:
                guard let network = snapshot.network else { continue }
                items.append(.rates(up: Format.rate(network.up), down: Format.rate(network.down)))
            }
        }
        return BarContent(items: items)
    }

    /// A share of the full height in steps. Anything above zero shows at least one step.
    public static func step(_ fraction: Double) -> UInt8 {
        guard fraction > 0 else { return 0 }
        return UInt8(max(1, min(Double(steps), (fraction * Double(steps)).rounded())))
    }
}
