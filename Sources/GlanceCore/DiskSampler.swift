import Darwin
import Foundation

public enum DiskSampler {
    /// The boot volume. Free space is the figure Finder shows, which counts
    /// space macOS can reclaim on demand.
    public static func read(path: String = "/") -> DiskReading? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
           let total = values.volumeTotalCapacity, total > 0,
           let free = values.volumeAvailableCapacityForImportantUsage, free > 0 {
            return DiskReading(total: UInt64(total), free: UInt64(free))
        }
        var stats = statfs()
        guard statfs(path, &stats) == 0, stats.f_blocks > 0 else { return nil }
        let blockSize = UInt64(stats.f_bsize)
        return DiskReading(total: UInt64(stats.f_blocks) * blockSize, free: UInt64(stats.f_bavail) * blockSize)
    }
}
