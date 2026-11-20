import Foundation

/// Finds the reading under the pointer in a chart of equal columns, newest on the right.
public enum ChartProbe {
    /// The column at `x`, counted from the left, or nil outside the chart.
    public static func slot(at x: Double, width: Double, slots: Int) -> Int? {
        guard width > 0, slots > 0, x >= 0, x < width else { return nil }
        return min(slots - 1, Int(x / width * Double(slots)))
    }

    /// The index into `count` values, oldest first, that column `slot` draws. A chart that is not
    /// full yet leaves its left columns empty: those have no value.
    public static func index(slot: Int, slots: Int, count: Int) -> Int? {
        let index = slot - (slots - count)
        return index >= 0 && index < count ? index : nil
    }

    /// Whole seconds between the reading at `index` and the newest one, from the times the
    /// readings were taken, oldest first. A changed refresh interval or a pause while the displays
    /// slept shows up as it happened. Nil when there is no reading at `index`.
    public static func age(index: Int, times: [Double]) -> Int? {
        guard times.indices.contains(index), let newest = times.last else { return nil }
        return max(0, Int((newest - times[index]).rounded()))
    }
}

extension Format {
    /// "now", "48s ago", "1m 36s ago", "3h 09m ago", "3d 9h ago".
    public static func ago(_ seconds: Int) -> String {
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return String(format: "%dm %02ds ago", seconds / 60, seconds % 60) }
        return "\(duration(TimeInterval(seconds))) ago"
    }

    /// "Core 3 · performance". Efficiency cores come first in the kernel's numbering; a Mac with
    /// one kind of core gets the number alone.
    public static func core(_ index: Int, efficiency: Int, total: Int) -> String {
        let name = "Core \(index + 1)"
        guard efficiency > 0, efficiency < total else { return name }
        return "\(name) · \(index < efficiency ? "efficiency" : "performance")"
    }

    /// "5h 12m left", "full in 42m", "on power".
    public static func batteryState(_ battery: BatteryReading) -> String {
        if battery.charging {
            return battery.minutesLeft.map { "full in \(duration(TimeInterval($0 * 60)))" } ?? "charging"
        }
        if battery.onAC { return "on power" }
        return battery.minutesLeft.map { "\(duration(TimeInterval($0 * 60))) left" } ?? "on battery"
    }
}

/// The menu bar item's readings in words, one line per meter in the item's order. The gauges
/// carry no figure in the menu bar: this is the text of the item's tooltip.
public enum BarSummary {
    public static func lines(snapshot: Snapshot, visible: [Meter]) -> [String] {
        visible.compactMap { meter in
            switch meter {
            case .cpu:
                snapshot.cpu.map {
                    "CPU \(Format.percent($0.total)): user \(Format.percent($0.user)), "
                        + "system \(Format.percent($0.system))"
                }
            case .gpu:
                snapshot.gpu.map { "GPU \(Format.percent($0))" }
            case .memory:
                snapshot.memory.map {
                    "Memory pressure \(Format.percent($0.pressureFraction)), "
                        + "\(Format.memory($0.used)) of \(Format.memory($0.total)) used"
                }
            case .disk:
                snapshot.disk.map {
                    "Disk \(Format.percent($0.usedFraction)) used, \(Format.storage($0.free)) free"
                }
            case .temperature:
                snapshot.temperature.map {
                    "CPU \(Format.degrees($0.average)), hottest core \(Format.degrees($0.hottest))"
                }
            case .battery:
                snapshot.battery.map { "Battery \($0.percent)%, \(Format.batteryState($0))" }
            case .network:
                snapshot.network.map { "Network up \(Format.rate($0.up)), down \(Format.rate($0.down))" }
            }
        }
    }
}
