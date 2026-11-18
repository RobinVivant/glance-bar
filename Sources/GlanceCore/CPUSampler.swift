import Darwin

/// The kernel's running tick counts for one CPU, or for all of them together.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUMath {
    /// The load between two tick counts, or nil when no time passed. The
    /// counters wrap, so the subtraction wraps with them.
    public static func load(from a: CPUTicks, to b: CPUTicks) -> CPULoad? {
        let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
        let system = Double(b.system &- a.system)
        let total = user + system + Double(b.idle &- a.idle)
        guard total > 0 else { return nil }
        return CPULoad(user: user / total, system: system / total)
    }
}

/// Reads CPU load from the Mach host. Each call reports the load since the
/// previous call, so the first one returns nil.
public final class CPUSampler {
    private let host = mach_host_self()
    private var last: CPUTicks?
    private var lastCores: [CPUTicks] = []

    public init() {}

    /// All cores together: one Mach call, no allocation.
    public func sample() -> CPULoad? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2,
                             nice: info.cpu_ticks.3)
        defer { last = ticks }
        return last.flatMap { CPUMath.load(from: $0, to: ticks) }
    }

    /// Load per core, 0 to 1 each. The kernel allocates the result, so this
    /// runs only while the panel is open.
    public func sampleCores() -> [Double]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var cores: [CPUTicks] = []
        cores.reserveCapacity(Int(cpuCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            cores.append(CPUTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                  system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                  idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                  nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        defer { lastCores = cores }
        guard lastCores.count == cores.count else { return nil }
        return zip(lastCores, cores).map { CPUMath.load(from: $0, to: $1)?.total ?? 0 }
    }

    /// Forgets the baseline, so the next reading does not average over the time nobody sampled.
    public func reset() { last = nil }

    /// Forgets the per-core baseline, so a later panel does not average over the time it was closed.
    public func forgetCores() { lastCores = [] }
}
