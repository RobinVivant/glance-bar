import Foundation
import IOKit
import IOKit.ps

public enum BatteryMath {
    /// One power source description from `IOPSGetPowerSourceDescription`, or
    /// nil when it is not an internal battery.
    public static func reading(from source: [String: Any]) -> BatteryReading? {
        guard source[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = source[kIOPSCurrentCapacityKey] as? Int,
              let maximum = source[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { return nil }
        let charging = source[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        // The system reports -1 while it is still working the estimate out.
        let minutes = source[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
        let estimate = (charging || !onAC) ? minutes.flatMap { $0 > 0 ? $0 : nil } : nil
        let percent = Int((Double(current) / Double(maximum) * 100).rounded())
        return BatteryReading(percent: min(100, max(0, percent)), charging: charging, onAC: onAC,
                              minutesLeft: estimate)
    }

    /// The registry keys `health(from:)` looks at.
    public static let healthKeys = ["CycleCount", "DesignCapacity", "NominalChargeCapacity", "AppleRawMaxCapacity",
                                    "BatteryData"]

    /// Properties of the `AppleSmartBattery` registry entry. macOS 27 moved the capacities from
    /// the entry itself into its `BatteryData` dictionary, so both places are read.
    public static func health(from properties: [String: Any]) -> BatteryHealth? {
        guard let cycles = (properties["CycleCount"] as? NSNumber)?.intValue else { return nil }
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        func positive(_ value: Any?) -> Double? {
            (value as? NSNumber).flatMap { $0.doubleValue > 0 ? $0.doubleValue : nil }
        }
        func capacity(_ key: String) -> Double? { positive(properties[key]) ?? positive(data[key]) }
        // The nominal capacity is the one behind Maximum Capacity in System Settings. The raw
        // one moves with every charge and reads a few points lower.
        guard let design = capacity("DesignCapacity"),
              let full = capacity("NominalChargeCapacity") ?? capacity("AppleRawMaxCapacity") else {
            return BatteryHealth(cycles: cycles)
        }
        // A new battery holds a little more than its design capacity.
        return BatteryHealth(cycles: cycles, capacity: min(100, Int((full / design * 100).rounded())))
    }
}

/// Battery wear, read only while the panel is open.
public struct BatteryHealth: Equatable, Sendable {
    public var cycles: Int
    /// What a full charge holds, in percent of what it held when new.
    public var capacity: Int?

    public init(cycles: Int, capacity: Int? = nil) {
        self.cycles = cycles
        self.capacity = capacity
    }
}

public enum BatterySampler {
    /// The internal battery, or nil on a Mac without one.
    public static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any], let reading = BatteryMath.reading(from: description) else { continue }
            return reading
        }
        return nil
    }

    public static func health() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: [String: Any] = [:]
        for key in BatteryMath.healthKeys {
            properties[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }
        return BatteryMath.health(from: properties)
    }
}
