import Darwin
import Foundation
import SystemConfiguration

/// Bytes an interface has carried since boot.
public struct InterfaceCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public enum NetworkMath {
    /// Rates between two readings keyed by interface. An interface that
    /// appeared in between, or whose counters went back to zero, adds nothing
    /// for this interval instead of a spike.
    public static func rates(previous: [UInt16: InterfaceCounters], current: [UInt16: InterfaceCounters],
                             elapsed: Double) -> NetworkRates? {
        guard elapsed > 0 else { return nil }
        var up = 0.0, down = 0.0
        for (index, now) in current {
            guard let before = previous[index], now.received >= before.received, now.sent >= before.sent
            else { continue }
            down += Double(now.received - before.received)
            up += Double(now.sent - before.sent)
        }
        return NetworkRates(up: up / elapsed, down: down / elapsed)
    }

    /// Physical interfaces only: Wi-Fi, Ethernet and tethering are all `en<digits>`.
    /// A VPN's `utun` traffic or pseudo-interfaces like `enc0` already cross one of them.
    public static func counts(interface name: String) -> Bool {
        name.hasPrefix("en") && name.count > 2 && name.dropFirst(2).allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Picks the primary physical interface's address: prefers macOS's routed `preferred`
    /// interface when it is among the non-link-local physical candidates (ignoring VPN `utun*`),
    /// otherwise the first non-link-local interface, falling back to link-local (`169.254.*`)
    /// only if nothing else exists.
    public static func selectPrimary(candidates: [(interface: String, address: String)],
                                     preferred: String?) -> (interface: String, address: String)? {
        let routable = candidates.filter { !$0.address.hasPrefix("169.254.") }
        if let preferred, let match = routable.first(where: { $0.interface == preferred }) {
            return match
        }
        return routable.first ?? candidates.first
    }
}

/// Reads the interface byte counters with one `sysctl` into a buffer the
/// sampler keeps, and turns them into rates since the previous call.
public final class NetworkSampler {
    private var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    private var capacity = 32 * 1024
    private var buffer: UnsafeMutableRawPointer
    private var previous: [UInt16: InterfaceCounters] = [:]
    private var current: [UInt16: InterfaceCounters] = [:]
    private var previousTime: UInt64 = 0
    private var counted: [UInt16: Bool] = [:]

    public init() {
        buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
    }

    deinit { buffer.deallocate() }

    /// Rates since the previous call; nil on the first one.
    public func sample() -> NetworkRates? {
        guard readCounters() else { return nil }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        defer {
            swap(&previous, &current)
            previousTime = now
        }
        guard previousTime != 0 else { return nil }
        return NetworkMath.rates(previous: previous, current: current, elapsed: Double(now - previousTime) / 1e9)
    }

    /// Bytes carried since boot over the counted interfaces, as of the last sample; nil before one.
    public var totals: InterfaceCounters? {
        guard previousTime != 0 else { return nil }
        return previous.values.reduce(into: InterfaceCounters(received: 0, sent: 0)) {
            $0.received += $1.received
            $0.sent += $1.sent
        }
    }

    /// Forgets the baseline, so the next rates do not average over the time nobody sampled.
    public func reset() {
        previous.removeAll(keepingCapacity: true)
        previousTime = 0
    }

    /// Interface numbers get reused when hardware comes and goes: look the names up again.
    public func forgetInterfaces() { counted.removeAll(keepingCapacity: true) }

    private func readCounters() -> Bool {
        var length = capacity
        while sysctl(&mib, u_int(mib.count), buffer, &length, nil, 0) != 0 {
            guard errno == ENOMEM, capacity < 4 * 1024 * 1024 else { return false }
            capacity *= 2
            buffer.deallocate()
            buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
            length = capacity
        }
        current.removeAll(keepingCapacity: true)
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if counts(message.ifm_index) {
                    current[message.ifm_index] = InterfaceCounters(received: message.ifm_data.ifi_ibytes,
                                                                   sent: message.ifm_data.ifi_obytes)
                }
            }
            offset += messageLength
        }
        return true
    }

    private func counts(_ index: UInt16) -> Bool {
        if let known = counted[index] { return known }
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        let interfaceName = if_indextoname(UInt32(index), &name) != nil
            ? String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self) : ""
        let result = !interfaceName.isEmpty && NetworkMath.counts(interface: interfaceName)
        counted[index] = result
        return result
    }

    /// The primary physical interface that is up with an IPv4 address, such as ("en0", "192.168.1.20").
    public static func primaryAddress() -> (interface: String, address: String)? {
        let preferred = (SCDynamicStoreCreate(nil, "GlanceBar" as CFString, nil, nil)
            .flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) }
            as? [String: Any])?["PrimaryInterface"] as? String
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(interface: String, address: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard NetworkMath.counts(interface: name) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                              NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            candidates.append((name, ip))
        }
        return NetworkMath.selectPrimary(candidates: candidates, preferred: preferred)
    }
}
