import Darwin
import Foundation

public enum MemoryMath {
    /// Splits page counts the way Activity Monitor does: app memory is the
    /// anonymous pages that cannot be purged, cached files are the file-backed
    /// and purgeable ones.
    public static func reading(pageSize: UInt64, total: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                               wiredPages: UInt64, compressorPages: UInt64, externalPages: UInt64,
                               pressure: Level, availablePercent: Int32) -> MemoryReading {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return MemoryReading(total: total, app: appPages * pageSize, wired: wiredPages * pageSize,
                             compressed: compressorPages * pageSize,
                             cached: (externalPages + purgeablePages) * pageSize, pressure: pressure,
                             pressureFraction: Double(100 - availablePercent) / 100)
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public static func pressure(kernelLevel: Int32) -> Level {
        kernelLevel >= 4 ? .critical : kernelLevel >= 2 ? .high : .normal
    }
}

public final class MemorySampler {
    private let host = mach_host_self()
    private let total = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64
    private var pressureMIB = [Int32](repeating: 0, count: 4)
    private var pressureMIBLength = 0
    private var availableMIB = [Int32](repeating: 0, count: 4)
    private var availableMIBLength = 0

    public init() {
        var size: vm_size_t = 0
        pageSize = host_page_size(host, &size) == KERN_SUCCESS ? UInt64(size) : UInt64(vm_kernel_page_size)
        var length = pressureMIB.count
        if sysctlnametomib("kern.memorystatus_vm_pressure_level", &pressureMIB, &length) == 0 {
            pressureMIBLength = length
        }
        length = availableMIB.count
        if sysctlnametomib("kern.memorystatus_level", &availableMIB, &length) == 0 {
            availableMIBLength = length
        }
    }

    public func sample() -> MemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryMath.reading(pageSize: pageSize, total: total, internalPages: UInt64(stats.internal_page_count),
                                  purgeablePages: UInt64(stats.purgeable_count), wiredPages: UInt64(stats.wire_count),
                                  compressorPages: UInt64(stats.compressor_page_count),
                                  externalPages: UInt64(stats.external_page_count),
                                  pressure: MemoryMath.pressure(
                                      kernelLevel: integer(&pressureMIB, pressureMIBLength) ?? 1),
                                  availablePercent: integer(&availableMIB, availableMIBLength) ?? 100)
    }

    /// One integer through a name looked up once at start.
    private func integer(_ mib: inout [Int32], _ length: Int) -> Int32? {
        guard length > 0 else { return nil }
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctl(&mib, u_int(length), &value, &size, nil, 0) == 0 ? value : nil
    }

    /// Bytes of swap in use.
    public static func swapUsed() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }
}
