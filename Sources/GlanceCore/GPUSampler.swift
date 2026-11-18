import Foundation
import IOKit

/// Reads GPU utilization from the graphics driver's statistics. The driver
/// objects are found once; each sample is one property read per GPU.
public final class GPUSampler {
    private var services: [io_service_t] = []

    public init() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            services.append(service)
        }
    }

    deinit { services.forEach { IOObjectRelease($0) } }

    /// The busiest GPU, 0 to 1, or nil when no driver reports a figure.
    public func sample() -> Double? {
        var busiest: Double?
        for service in services {
            let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)
            guard let stats = property?.takeRetainedValue() as? NSDictionary,
                  let percent = stats["Device Utilization %"] as? NSNumber else { continue }
            busiest = max(busiest ?? 0, min(1, max(0, percent.doubleValue / 100)))
        }
        return busiest
    }
}
