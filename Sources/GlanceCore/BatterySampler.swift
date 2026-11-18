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
}

/// Battery wear, read only while the panel is open.
public struct BatteryHealth: Equatable, Sendable {
    public var cycles: Int

    public init(cycles: Int) {
        self.cycles = cycles
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
        func number(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.intValue
        }
        return number("CycleCount").map(BatteryHealth.init)
    }
}
