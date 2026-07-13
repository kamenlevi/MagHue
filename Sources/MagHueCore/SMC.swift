import Foundation
import IOKit

/// Minimal AppleSMC client: just enough to read key info and write one key.
/// Struct layout mirrors the kernel's SMCParamStruct (80 bytes); the explicit
/// `padding` field keeps Swift's layout in sync with the C definition.
public enum SMC {
    public enum SMCError: Error, CustomStringConvertible {
        case serviceNotFound
        case openFailed(kern_return_t)
        case callFailed(kern_return_t)
        case smcResult(UInt8)
        case unexpectedLayout(Int)

        public var description: String {
            switch self {
            case .serviceNotFound: return "AppleSMC service not found"
            case .openFailed(let kr): return "IOServiceOpen failed (\(kr))"
            case .callFailed(let kr): return "IOConnectCallStructMethod failed (\(kr))"
            case .smcResult(let r):
                return r == 0x84 ? "SMC key not found (this Mac may not support the MagSafe LED)"
                                 : "SMC returned error \(r)"
            case .unexpectedLayout(let size):
                return "SMCParamStruct has unexpected size \(size), refusing to talk to the SMC"
            }
        }
    }

    struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCWriteKey: UInt8 = 6
    private static let kSMCGetKeyFromIndex: UInt8 = 8
    private static let kSMCGetKeyInfo: UInt8 = 9

    public static func fourCC(_ code: String) -> UInt32 {
        precondition(code.utf8.count == 4, "SMC keys are 4 characters")
        return code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func withConnection<T>(_ body: (io_connect_t) throws -> T) throws -> T {
        guard MemoryLayout<SMCParamStruct>.stride == 80 else {
            throw SMCError.unexpectedLayout(MemoryLayout<SMCParamStruct>.stride)
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
        defer { IOServiceClose(connection) }
        return try body(connection)
    }

    private static func call(_ connection: io_connect_t,
                             _ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent,
                                           &input, MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outputSize)
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }

    /// Returns the data size/type for a key. Also serves as an unprivileged
    /// probe for whether this Mac has the key at all.
    public static func keyInfo(_ key: String) throws -> (size: UInt32, type: String) {
        try withConnection { connection in
            var request = SMCParamStruct()
            request.key = fourCC(key)
            request.data8 = kSMCGetKeyInfo
            let reply = try call(connection, request)
            let t = reply.keyInfo.dataType
            let type = String(bytes: [UInt8(t >> 24 & 0xff), UInt8(t >> 16 & 0xff),
                                      UInt8(t >> 8 & 0xff), UInt8(t & 0xff)],
                              encoding: .ascii) ?? "????"
            return (reply.keyInfo.dataSize, type)
        }
    }

    /// Lists every key the SMC exposes. Works unprivileged; diagnostic use.
    public static func allKeys() throws -> [String] {
        try withConnection { connection in
            var countRequest = SMCParamStruct()
            countRequest.key = fourCC("#KEY")
            countRequest.data8 = kSMCReadKey
            countRequest.keyInfo.dataSize = 4
            let countReply = try call(connection, countRequest)
            let count = UInt32(countReply.bytes.0) << 24 | UInt32(countReply.bytes.1) << 16
                      | UInt32(countReply.bytes.2) << 8 | UInt32(countReply.bytes.3)

            var keys: [String] = []
            for index in 0..<count {
                var request = SMCParamStruct()
                request.data8 = kSMCGetKeyFromIndex
                request.data32 = index
                guard let reply = try? call(connection, request) else { continue }
                let k = reply.key
                if let name = String(bytes: [UInt8(k >> 24 & 0xff), UInt8(k >> 16 & 0xff),
                                             UInt8(k >> 8 & 0xff), UInt8(k & 0xff)],
                                     encoding: .ascii) {
                    keys.append(name)
                }
            }
            return keys
        }
    }

    /// Reads a key's raw bytes. Works unprivileged.
    public static func readBytes(_ key: String) throws -> [UInt8] {
        try withConnection { connection in
            var info = SMCParamStruct()
            info.key = fourCC(key)
            info.data8 = kSMCGetKeyInfo
            let infoReply = try call(connection, info)

            var request = SMCParamStruct()
            request.key = fourCC(key)
            request.data8 = kSMCReadKey
            request.keyInfo.dataSize = infoReply.keyInfo.dataSize
            let reply = try call(connection, request)
            return withUnsafeBytes(of: reply.bytes) {
                Array($0.prefix(Int(infoReply.keyInfo.dataSize)))
            }
        }
    }

    /// Reads a single-byte SMC key. Works unprivileged.
    public static func readByte(_ key: String) throws -> UInt8 {
        try readBytes(key).first ?? 0
    }

    /// Writes a single-byte SMC key. Requires root.
    public static func writeByte(_ key: String, _ value: UInt8) throws {
        try withConnection { connection in
            var info = SMCParamStruct()
            info.key = fourCC(key)
            info.data8 = kSMCGetKeyInfo
            let infoReply = try call(connection, info)

            var request = SMCParamStruct()
            request.key = fourCC(key)
            request.data8 = kSMCWriteKey
            request.keyInfo.dataSize = infoReply.keyInfo.dataSize
            request.bytes.0 = value
            _ = try call(connection, request)
        }
    }
}

/// The MagSafe LED control key on Apple Silicon MacBooks.
public enum MagSafeLED {
    public static let key = "ACLC"

    public enum Color: UInt8 {
        case system = 0
        case off = 1
        case green = 3
        /// The standard "still charging" color — amber, as Apple calls it.
        case amber = 4
    }

    public static func set(_ color: Color) throws {
        try SMC.writeByte(key, color.rawValue)
    }

    /// True if this Mac exposes the MagSafe LED key at all.
    public static func isSupported() -> Bool {
        (try? SMC.keyInfo(key)) != nil
    }
}

/// The firmware-managed charge limit on modern Apple Silicon (macOS 26-era).
/// macOS's own "Charge Limit / Optimized Battery Charging" is enforced through
/// this key set; the firmware keeps the battery within [lower, upper] itself.
///
/// - `bfF0` activation: 0x00 = off (charge to 100%), 0x02 = limit active.
/// - `bfD0` upper / `bfE0` lower: percentages, low byte first.
///
/// These are the same keys and write semantics that `batt` and AlDente use.
/// The one-shot "Charge to Full" sets activation to 0x00 and later restores
/// the saved limit. If the full key set isn't present (as on some firmware
/// revisions), `isSupported()` is false and MagHue writes nothing.
public enum ChargeLimit {
    static let activationKey = "bfF0"
    static let upperKey = "bfD0"
    static let lowerKey = "bfE0"

    public struct State: Equatable {
        public var active: Bool
        public var lower: Int
        public var upper: Int
        public init(active: Bool, lower: Int, upper: Int) {
            self.active = active
            self.lower = lower
            self.upper = upper
        }
    }

    /// True only when every key needed to lift *and* restore the limit is
    /// present. Unprivileged, so the app can gate the UI with it.
    public static func isSupported() -> Bool {
        (try? SMC.keyInfo(activationKey)) != nil
            && (try? SMC.keyInfo(upperKey)) != nil
            && (try? SMC.keyInfo(lowerKey)) != nil
    }

    public static func read() throws -> State {
        State(active: try SMC.readByte(activationKey) == 0x02,
              lower: try readPercent(lowerKey),
              upper: try readPercent(upperKey))
    }

    private static func readPercent(_ key: String) throws -> Int {
        // Percentages are stored low byte first.
        Int(try SMC.readBytes(key).first ?? 0)
    }

    /// Lift the limit so the battery charges to 100%. Requires root.
    public static func disable() throws {
        try SMC.writeByte(activationKey, 0x00)
    }

    /// Restore an active limit with the given bounds. Write order matters and
    /// mirrors the firmware's expected sequence. Requires root.
    public static func enable(lower: Int, upper: Int) throws {
        try SMC.writeByte(activationKey, 0x00)
        // writeByte pads the remaining bytes with zero, giving the correct
        // low-byte-first percentage for these multi-byte keys.
        try SMC.writeByte(upperKey, UInt8(min(max(upper, 0), 100)))
        try SMC.writeByte(lowerKey, UInt8(min(max(lower, 0), 100)))
        try SMC.writeByte(activationKey, 0x02)
    }
}
