import Foundation
import IOKit

/// The 80-byte request and reply the AppleSMC driver exchanges, addressed by
/// byte offset so nothing depends on how Swift would lay out the C struct.
public enum SMCPacket {
    public static let size = 80
    public static let keyOffset = 0
    public static let dataSizeOffset = 28
    public static let dataTypeOffset = 32
    public static let resultOffset = 40
    public static let commandOffset = 42
    public static let bytesOffset = 48

    public static let readBytes: UInt8 = 5
    public static let readKeyInfo: UInt8 = 9
    /// The driver's selector for every key operation.
    public static let selector: UInt32 = 2

    /// "Tp01" as the four-character code the driver expects.
    public static func code(_ name: String) -> UInt32 {
        name.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    public static let floatType = code("flt ")

    public static func write(key: UInt32, command: UInt8, dataSize: UInt32, into packet: UnsafeMutableRawPointer) {
        packet.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        packet.storeBytes(of: key, toByteOffset: keyOffset, as: UInt32.self)
        packet.storeBytes(of: dataSize, toByteOffset: dataSizeOffset, as: UInt32.self)
        packet.storeBytes(of: command, toByteOffset: commandOffset, as: UInt8.self)
    }
}

/// A read-only connection to the System Management Controller, which holds
/// the temperature sensors on Apple silicon.
public final class SMC {
    /// A key known to exist and to hold a 32-bit float.
    public struct Key: Equatable, Sendable {
        public let code: UInt32
        let size: UInt32
    }

    private var connection: io_connect_t = 0
    private let input = UnsafeMutableRawPointer.allocate(byteCount: SMCPacket.size, alignment: 8)
    private let output = UnsafeMutableRawPointer.allocate(byteCount: SMCPacket.size, alignment: 8)

    /// Nil on a Mac without the service, such as a virtual machine.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            connection = 0
            return nil
        }
    }

    /// Runs after a failed `init?` too, so this is the only place that frees the buffers.
    deinit {
        if connection != 0 { IOServiceClose(connection) }
        input.deallocate()
        output.deallocate()
    }

    private func call(key: UInt32, command: UInt8, dataSize: UInt32) -> Bool {
        SMCPacket.write(key: key, command: command, dataSize: dataSize, into: input)
        output.initializeMemory(as: UInt8.self, repeating: 0, count: SMCPacket.size)
        var outputSize = SMCPacket.size
        return IOConnectCallStructMethod(connection, SMCPacket.selector, input, SMCPacket.size, output,
                                         &outputSize) == KERN_SUCCESS
            && outputSize == SMCPacket.size
            && output.load(fromByteOffset: SMCPacket.resultOffset, as: UInt8.self) == 0
    }

    /// The key, when this Mac has it and it holds a float.
    public func floatKey(_ name: String) -> Key? {
        let code = SMCPacket.code(name)
        guard call(key: code, command: SMCPacket.readKeyInfo, dataSize: 0),
              output.load(fromByteOffset: SMCPacket.dataTypeOffset, as: UInt32.self) == SMCPacket.floatType,
              output.load(fromByteOffset: SMCPacket.dataSizeOffset, as: UInt32.self) == 4 else { return nil }
        return Key(code: code, size: 4)
    }

    public func read(_ key: Key) -> Double? {
        guard call(key: key.code, command: SMCPacket.readBytes, dataSize: key.size) else { return nil }
        return Double(output.loadUnaligned(fromByteOffset: SMCPacket.bytesOffset, as: Float.self))
    }
}
