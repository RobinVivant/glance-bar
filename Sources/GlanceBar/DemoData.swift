import Foundation
import GlanceCore

/// Made-up readings for `--demo`: a Mac under moderate load, with no reading
/// taken from the real one. README images come from these.
enum DemoData {
    static let machine = Machine(chip: "Apple M1 Max", cores: 10, efficiencyCores: 2, memory: 64 << 30)

    static var snapshot: Snapshot {
        var snapshot = Snapshot()
        snapshot.cpu = CPULoad(user: 0.27, system: 0.09)
        snapshot.gpu = 0.18
        snapshot.memory = MemoryReading(total: 64 << 30, app: 27 << 30, wired: 5 << 30, compressed: 6 << 30,
                                        cached: 14 << 30, pressure: .normal, pressureFraction: 0.24)
        snapshot.temperature = CPUTemperature(average: 58, hottest: 67)
        snapshot.battery = BatteryReading(percent: 84, charging: false, onAC: false, minutesLeft: 312)
        snapshot.network = NetworkRates(up: 184_000, down: 2_400_000)
        snapshot.disk = DiskReading(total: 994_000_000_000, free: 412_000_000_000)
        return snapshot
    }

    static var detail: Detail {
        Detail(cores: [0.62, 0.55, 0.48, 0.41, 0.36, 0.22, 0.31, 0.12, 0.09, 0.05], gpuTemperature: 52,
               batteryTemperature: 31, storageTemperature: 38, swapUsed: 1_300_000_000, loadAverage: 3.42,
               uptime: 3 * 86_400 + 9 * 3600, batteryHealth: BatteryHealth(cycles: 212, capacity: 91),
               interface: "en0", address: "192.168.1.20",
               networkTotals: InterfaceCounters(received: 48_200_000_000, sent: 6_100_000_000),
               appCPU: 0.011, appMemory: 31 << 20)
    }

    /// A repeatable wave with bursts, ending on the snapshot's current value.
    private static func wave(count: Int, base: Double, swing: Double, burstEvery: Int, burst: Double,
                             last: Double) -> [Float] {
        var values = (0..<count).map { index -> Float in
            let x = Double(index)
            let ripple = sin(x * 0.45) * 0.5 + sin(x * 1.3 + 1) * 0.3 + sin(x * 0.13) * 0.2
            let spike = index % burstEvery < 3 ? burst * (1 - Double(index % burstEvery) / 3) : 0
            return Float(max(0, base + swing * ripple + spike))
        }
        values[count - 1] = Float(last)
        return values
    }

    static let cpuHistory = wave(count: Monitor.historyLength, base: 0.26, swing: 0.14, burstEvery: 17, burst: 0.45,
                                 last: 0.36)
    static let upHistory = wave(count: Monitor.historyLength, base: 150_000, swing: 110_000, burstEvery: 23,
                                burst: 500_000, last: 184_000)
    static let downHistory = wave(count: Monitor.historyLength, base: 1_500_000, swing: 1_100_000, burstEvery: 13,
                                  burst: 3_800_000, last: 2_400_000)

    /// One reading every 2 seconds, the default refresh interval.
    static let times = (0..<Monitor.historyLength).map { Double($0) * 2 }

    static func history<Element>(_ values: [Element]) -> History<Element> {
        var history = History<Element>(capacity: Monitor.historyLength)
        values.forEach { history.append($0) }
        return history
    }
}
