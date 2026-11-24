import Foundation

public enum Format {
    /// "0 KB/s", "12 KB/s", "1.4 MB/s", "12 MB/s", "1.2 GB/s": at most three digits, so the
    /// menu bar slot keeps one width.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let kb = max(0, bytesPerSecond) / 1000
        if kb < 999.5 { return "\(Int(kb.rounded())) KB/s" }
        let mb = kb / 1000
        if mb < 9.95 { return String(format: "%.1f MB/s", mb) }
        if mb < 999.5 { return "\(Int(mb.rounded())) MB/s" }
        let gb = mb / 1000
        if gb < 9.95 { return String(format: "%.1f GB/s", gb) }
        return "\(Int(min(999, gb.rounded()))) GB/s"
    }

    /// Memory, counted in powers of 1024 as Activity Monitor does: "41.2 GB", "512 MB".
    public static func memory(_ bytes: UInt64) -> String {
        let mb = (Double(bytes) / 1_048_576).rounded()
        if mb < 1024 { return "\(Int(mb)) MB" }
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 99.95 ? "\(Int(gb.rounded())) GB" : "\(trimmed(gb)) GB"
    }

    /// Storage and transfer totals, counted in powers of 1000 as Finder does: "412 GB", "1.2 TB".
    public static func storage(_ bytes: UInt64) -> String {
        let mb = (Double(bytes) / 1e6).rounded()
        if mb < 1000 { return "\(Int(mb)) MB" }
        let gb = Double(bytes) / 1e9
        if gb >= 999.5 { return String(format: "%.2f TB", gb / 1000) }
        return gb >= 99.95 ? "\(Int(gb.rounded())) GB" : "\(trimmed(gb)) GB"
    }

    /// One decimal, dropped when it is zero: "41.2", "64".
    static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    public static func degrees(_ celsius: Double, unit: TemperatureUnit = .celsius) -> String {
        let value = unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// Power draw or charge rate: "8.4 W", "14.2 W", "105 W".
    public static func watts(_ watts: Double) -> String {
        let value = max(0, watts)
        return value >= 99.95 ? "\(Int(value.rounded())) W" : "\(trimmed(value)) W"
    }

    /// "42m", "3h 09m", "3d 9h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return String(format: "%dh %02dm", hours, minutes % 60) }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
