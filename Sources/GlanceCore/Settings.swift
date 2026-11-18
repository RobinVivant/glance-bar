import Foundation

/// One readout in the menu bar.
public enum Meter: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, temperature, battery, network

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .temperature: "Temperature"
        case .battery: "Battery"
        case .network: "Network"
        }
    }

    /// The three letters stacked beside a graph or gauge.
    public var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "MEM"
        case .disk: "SSD"
        default: ""
        }
    }
}

/// What the menu bar shows and how often it refreshes.
public struct BarSettings: Codable, Equatable, Sendable {
    public static let intervals = [1, 2, 3, 5]
    public static let defaultsKey = "barSettings"

    /// Every meter, left to right, hidden ones included.
    public var order: [Meter] = Meter.allCases
    public var hidden: Set<Meter> = []
    /// Seconds between samples.
    public var interval = 2

    public init() {}

    private enum CodingKeys: String, CodingKey { case order, hidden, interval }

    /// Reads meters by name and skips the ones this version does not know, so
    /// settings written by another version still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = (try container.decodeIfPresent([String].self, forKey: .order) ?? []).compactMap(Meter.init)
        hidden = Set((try container.decodeIfPresent([String].self, forKey: .hidden) ?? []).compactMap(Meter.init))
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 2
        self = normalized()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order.map(\.rawValue), forKey: .order)
        try container.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        try container.encode(interval, forKey: .interval)
    }

    public var visible: [Meter] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ meter: Meter) -> Bool { !hidden.contains(meter) }

    public mutating func setVisible(_ meter: Meter, _ visible: Bool) {
        if visible { hidden.remove(meter) } else { hidden.insert(meter) }
    }

    /// Moves a meter one place left (-1) or right (+1); a move off either end does nothing.
    public mutating func move(_ meter: Meter, by offset: Int) {
        guard let index = order.firstIndex(of: meter) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    /// Each meter exactly once, and an interval the app offers.
    public func normalized() -> BarSettings {
        var result = self
        var seen = Set<Meter>()
        result.order = order.filter { seen.insert($0).inserted } + Meter.allCases.filter { !order.contains($0) }
        if !Self.intervals.contains(interval) { result.interval = 2 }
        return result
    }

    public static func load(from defaults: UserDefaults) -> BarSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(BarSettings.self, from: data) else { return BarSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
