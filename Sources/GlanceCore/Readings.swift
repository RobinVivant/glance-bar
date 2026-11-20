import Foundation

/// How worrying a reading is. The menu bar stays monochrome at `normal` and
/// turns amber at `high` and red at `critical`.
public enum Level: Int, Comparable, Sendable {
    case normal, high, critical

    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
}

/// CPU time shares between two samples, each 0 to 1.
public struct CPULoad: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var total: Double { min(1, user + system) }

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }
}

/// Memory in bytes, split the way Activity Monitor splits "Memory Used".
public struct MemoryReading: Equatable, Sendable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    /// The kernel's own verdict, which is what colors the meter.
    public var pressure: Level
    /// Memory pressure, 0 to 1: the share of memory the system can no longer hand out freely. This
    /// is the figure Activity Monitor graphs, and what the menu bar gauge shows.
    public var pressureFraction: Double

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, pressure: Level,
                pressureFraction: Double) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.pressure = pressure
        self.pressureFraction = min(1, max(0, pressureFraction))
    }
}

/// Bytes per second over all physical interfaces.
public struct NetworkRates: Equatable, Sendable {
    public var up: Double
    public var down: Double

    public init(up: Double, down: Double) {
        self.up = up
        self.down = down
    }
}

public struct BatteryReading: Equatable, Sendable {
    public var percent: Int
    public var charging: Bool
    public var onAC: Bool
    /// Minutes until empty on battery, or until full while charging.
    public var minutesLeft: Int?

    public init(percent: Int, charging: Bool, onAC: Bool, minutesLeft: Int? = nil) {
        self.percent = percent
        self.charging = charging
        self.onAC = onAC
        self.minutesLeft = minutesLeft
    }
}

public struct DiskReading: Equatable, Sendable {
    public var total: UInt64
    public var free: UInt64

    public var usedFraction: Double { total == 0 ? 0 : min(1, max(0, 1 - Double(free) / Double(total))) }

    public init(total: UInt64, free: UInt64) {
        self.total = total
        self.free = free
    }
}

/// Degrees Celsius over the CPU cores.
public struct CPUTemperature: Equatable, Sendable {
    public var average: Double
    public var hottest: Double

    public init(average: Double, hottest: Double) {
        self.average = average
        self.hottest = hottest
    }
}

/// Everything the menu bar shows. A nil field has no reading: the Mac lacks
/// the part (a desktop has no battery) or nothing asked for it yet.
public struct Snapshot: Equatable, Sendable {
    public var cpu: CPULoad?
    /// GPU utilization, 0 to 1.
    public var gpu: Double?
    public var memory: MemoryReading?
    public var temperature: CPUTemperature?
    public var battery: BatteryReading?
    public var network: NetworkRates?
    public var disk: DiskReading?

    public init() {}
}

/// The thresholds behind the amber and red states.
public enum Levels {
    public static func load(_ fraction: Double) -> Level {
        fraction >= 0.95 ? .critical : fraction >= 0.85 ? .high : .normal
    }

    public static func temperature(_ celsius: Double) -> Level {
        celsius >= 100 ? .critical : celsius >= 90 ? .high : .normal
    }

    public static func storageTemperature(_ celsius: Double) -> Level {
        celsius >= 75 ? .critical : celsius >= 65 ? .high : .normal
    }

    public static func batteryTemperature(_ celsius: Double) -> Level {
        celsius >= 45 ? .critical : celsius >= 40 ? .high : .normal
    }

    public static func disk(_ usedFraction: Double) -> Level {
        usedFraction >= 0.95 ? .critical : usedFraction >= 0.9 ? .high : .normal
    }

    /// Low only counts while the Mac runs on its battery.
    public static func battery(_ battery: BatteryReading) -> Level {
        guard !battery.onAC else { return .normal }
        return battery.percent <= 10 ? .critical : battery.percent <= 20 ? .high : .normal
    }

    /// Below 80% of its original capacity, Apple counts a battery as worn.
    public static func batteryHealth(_ capacity: Int) -> Level {
        capacity < 80 ? .high : .normal
    }
}
