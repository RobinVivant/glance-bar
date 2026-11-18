/// The last `capacity` values of a reading, oldest first. A ring: appending
/// never allocates once the buffer is full.
public struct History: Equatable, Sendable {
    public let capacity: Int
    private var storage: [Float] = []
    private var head = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var last: Float? { storage.isEmpty ? nil : storage[(head + storage.count - 1) % storage.count] }

    public mutating func append(_ value: Float) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[head] = value
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Oldest first.
    public var values: [Float] { suffix(storage.count) }

    /// The newest `count` values, oldest first.
    public func suffix(_ count: Int) -> [Float] {
        let n = min(max(0, count), storage.count)
        var result: [Float] = []
        result.reserveCapacity(n)
        let start = head + storage.count - n
        for offset in 0..<n { result.append(storage[(start + offset) % storage.count]) }
        return result
    }
}
