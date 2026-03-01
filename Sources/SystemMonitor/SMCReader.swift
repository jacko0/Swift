import Foundation
import IOKit

// Communicates with the AppleSMC kernel extension using raw byte buffers.
// The kernel's SMCKeyData_t is 80 bytes. Swift structs can't reproduce the
// exact C layout due to alignment differences, so we place fields at their
// empirically verified offsets.
//
// Verified offsets (macOS on Apple Silicon & Intel):
//   0:  key             UInt32 (native endian)
//  28:  keyInfo.dataSize UInt32
//  32:  keyInfo.dataType UInt32 (FourCC, big-endian encoded)
//  42:  data8            UInt8  — command selector
//  48:  bytes[32]        — output/input data
final class SMCReader {
    static let shared = SMCReader()

    private var conn: io_connect_t = 0
    private let kStructSize = 80

    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCCmdReadKeyInfo: UInt8 = 9
    private let kSMCCmdReadBytes:   UInt8 = 5

    private let kOffKey:      Int = 0
    private let kOffDataSize: Int = 28
    private let kOffDataType: Int = 32
    private let kOffData8:    Int = 42
    private let kOffBytes:    Int = 48

    init() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleSMC"),
                                           &iter) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iter) }
        let device = IOIteratorNext(iter)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }
        IOServiceOpen(device, mach_task_self_, 0, &conn)
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    // MARK: - Private helpers

    private func fourCC(_ s: String) -> UInt32 {
        let b = Array(s.utf8)
        guard b.count == 4 else { return 0 }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    private func smcCall(_ input: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        guard conn != 0 else { return nil }
        let output = UnsafeMutableRawPointer.allocate(byteCount: kStructSize, alignment: 4)
        memset(output, 0, kStructSize)
        var outSize = kStructSize
        let r = IOConnectCallStructMethod(conn,
                                          kSMCHandleYPCEvent,
                                          input, kStructSize,
                                          output, &outSize)
        guard r == kIOReturnSuccess else {
            output.deallocate()
            return nil
        }
        return output
    }

    private func readKeyInfo(key: UInt32) -> (size: UInt32, type: UInt32)? {
        let input = UnsafeMutableRawPointer.allocate(byteCount: kStructSize, alignment: 4)
        memset(input, 0, kStructSize)
        defer { input.deallocate() }

        var k = key; memcpy(input + kOffKey, &k, 4)
        input.storeBytes(of: kSMCCmdReadKeyInfo, toByteOffset: kOffData8, as: UInt8.self)

        guard let output = smcCall(input) else { return nil }
        defer { output.deallocate() }

        var dataSize: UInt32 = 0; memcpy(&dataSize, output + kOffDataSize, 4)
        var dataType: UInt32 = 0; memcpy(&dataType, output + kOffDataType, 4)
        guard dataSize > 0 else { return nil }
        return (dataSize, dataType)
    }

    /// Read a named SMC key, returning its raw bytes and type FourCC.
    private func readKey(_ key: String) -> (bytes: [UInt8], type: UInt32)? {
        let k = fourCC(key)
        guard let info = readKeyInfo(key: k) else { return nil }

        let input = UnsafeMutableRawPointer.allocate(byteCount: kStructSize, alignment: 4)
        memset(input, 0, kStructSize)
        defer { input.deallocate() }

        var kk = k; memcpy(input + kOffKey, &kk, 4)
        var ds = info.size; memcpy(input + kOffDataSize, &ds, 4)
        input.storeBytes(of: kSMCCmdReadBytes, toByteOffset: kOffData8, as: UInt8.self)

        guard let output = smcCall(input) else { return nil }
        defer { output.deallocate() }

        let count = Int(info.size)
        let ptr = output.advanced(by: kOffBytes).assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: ptr, count: min(count, 32))), info.type)
    }

    /// Interpret raw SMC bytes as a temperature in °C based on the data type.
    private func decodeTemperature(bytes: [UInt8], type: UInt32) -> Double? {
        let typeFourCC = withUnsafeBytes(of: type.bigEndian) { String(bytes: $0, encoding: .ascii) }
        if typeFourCC == "flt " && bytes.count >= 4 {
            // IEEE 754 float (Apple Silicon)
            var f: Float = 0
            bytes.withUnsafeBufferPointer { memcpy(&f, $0.baseAddress!, 4) }
            let temp = Double(f)
            if temp > 1 && temp < 150 { return temp }
        } else if bytes.count >= 2 {
            // SP78: signed fixed-point 8.8 (Intel)
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let temp = Double(Int16(bitPattern: raw)) / 256.0
            if temp > 1 && temp < 150 { return temp }
        }
        return nil
    }

    /// Interpret raw SMC bytes as a fan RPM based on the data type.
    private func decodeFanRPM(bytes: [UInt8], type: UInt32) -> Int? {
        let typeFourCC = withUnsafeBytes(of: type.bigEndian) { String(bytes: $0, encoding: .ascii) }
        if typeFourCC == "flt " && bytes.count >= 4 {
            // IEEE 754 float (Apple Silicon)
            var f: Float = 0
            bytes.withUnsafeBufferPointer { memcpy(&f, $0.baseAddress!, 4) }
            let rpm = Int(f)
            return rpm > 0 ? rpm : nil
        } else if bytes.count >= 2 {
            // FPE2: unsigned fixed-point 14.2 (Intel)
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let rpm = Int(raw) >> 2
            return rpm > 0 ? rpm : nil
        }
        return nil
    }

    // MARK: - Public API

    /// CPU temperature in °C.
    func cpuTemperature() -> Double? {
        // Apple Silicon keys first (Tp09 = P-core, Tp01 = E-core),
        // then Intel keys (TC0P = proximity, TC0D = die).
        for key in ["Tp09", "Tp01", "Tp0D", "Tp0H", "TC0P", "TC0D", "TCXC", "TC0E", "TC0F"] {
            guard let (bytes, type) = readKey(key) else { continue }
            if let temp = decodeTemperature(bytes: bytes, type: type) {
                return temp
            }
        }
        return nil
    }

    /// Fan speeds in RPM for all fans present.
    func fanSpeeds() -> [Int] {
        guard let (numBytes, _) = readKey("FNum"), !numBytes.isEmpty else {
            return []
        }
        // FNum is either a single UInt8 or a float depending on platform
        let fanCount: Int
        if numBytes.count >= 4 {
            var f: Float = 0
            numBytes.withUnsafeBufferPointer { memcpy(&f, $0.baseAddress!, 4) }
            fanCount = Int(f)
        } else {
            fanCount = Int(numBytes[0])
        }
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).compactMap { i in
            guard let (bytes, type) = readKey("F\(i)Ac") else { return nil }
            return decodeFanRPM(bytes: bytes, type: type)
        }
    }
}
