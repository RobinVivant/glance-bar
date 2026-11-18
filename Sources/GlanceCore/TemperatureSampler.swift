import Darwin
import Foundation

/// Which SMC keys hold the core temperatures. They differ per chip
/// generation; the lists follow the Stats project (github.com/exelban/stats).
/// Only the M1 list is checked on real hardware here, where its average
/// matches the CPU temperature iStat Menus shows.
public struct SensorKeys: Equatable, Sendable {
    public var cpu: [String]
    public var gpu: [String]

    static let generations: [Int: SensorKeys] = [
        1: SensorKeys(cpu: ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
                      gpu: ["Tg05", "Tg0D", "Tg0L", "Tg0T"]),
        2: SensorKeys(cpu: ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f",
                            "Tp0j"],
                      gpu: ["Tg0f", "Tg0j"]),
        3: SensorKeys(cpu: ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44",
                            "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
                      gpu: ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]),
        4: SensorKeys(cpu: ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b",
                            "Tp0e"],
                      gpu: ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]),
        5: SensorKeys(cpu: ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a",
                            "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"],
                      gpu: ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]),
    ]

    /// The keys for a chip named like "Apple M1 Max". An unknown chip gets
    /// every known key; the sampler keeps the ones the Mac actually has.
    public static func forChip(_ brand: String) -> SensorKeys {
        if let generation = generation(of: brand), let keys = generations[generation] { return keys }
        var all = SensorKeys(cpu: [], gpu: [])
        for generation in generations.keys.sorted() {
            guard let keys = generations[generation] else { continue }
            for key in keys.cpu where !all.cpu.contains(key) { all.cpu.append(key) }
            for key in keys.gpu where !all.gpu.contains(key) { all.gpu.append(key) }
        }
        return all
    }

    /// 1 for "Apple M1 Max", 4 for "Apple M4", nil for anything else.
    public static func generation(of brand: String) -> Int? {
        for word in brand.split(separator: " ") where word.first == "M" {
            if let number = Int(word.dropFirst()) { return number }
        }
        return nil
    }
}

public enum TemperatureMath {
    /// Average and hottest of the plausible readings. A sensor that is off reports 0 or a wild value.
    public static func summarize(_ values: [Double]) -> CPUTemperature? {
        let valid = values.filter { $0 > 0 && $0 < 130 }
        guard let hottest = valid.max() else { return nil }
        return CPUTemperature(average: valid.reduce(0, +) / Double(valid.count), hottest: hottest)
    }
}

public final class TemperatureSampler {
    private let smc: SMC?
    private var cpuKeys: [SMC.Key] = []
    private var gpuKeys: [SMC.Key] = []
    private var batteryKey: SMC.Key?
    private var storageKey: SMC.Key?
    private var scratch: [Double] = []

    public static var chipName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    public init(chip: String = TemperatureSampler.chipName) {
        smc = SMC()
        guard let smc else { return }
        let keys = SensorKeys.forChip(chip)
        cpuKeys = keys.cpu.compactMap(smc.floatKey)
        gpuKeys = keys.gpu.compactMap(smc.floatKey)
        batteryKey = smc.floatKey("TB0T")
        storageKey = smc.floatKey("TH0x")
        scratch.reserveCapacity(max(cpuKeys.count, gpuKeys.count))
    }

    private func read(_ keys: [SMC.Key]) -> CPUTemperature? {
        guard let smc, !keys.isEmpty else { return nil }
        scratch.removeAll(keepingCapacity: true)
        for key in keys {
            if let value = smc.read(key) { scratch.append(value) }
        }
        return TemperatureMath.summarize(scratch)
    }

    public func cpu() -> CPUTemperature? { read(cpuKeys) }
    public func gpu() -> Double? { read(gpuKeys)?.average }
    public func battery() -> Double? { batteryKey.flatMap { read([$0])?.average } }
    public func storage() -> Double? { storageKey.flatMap { read([$0])?.average } }
}
