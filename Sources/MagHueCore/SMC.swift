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
    private static let kSMCWriteKey: UInt8 = 6
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
        /// The standard "still charging" color; a reddish amber in person.
        case red = 4
    }

    public static func set(_ color: Color) throws {
        try SMC.writeByte(key, color.rawValue)
    }

    /// True if this Mac exposes the MagSafe LED key at all.
    public static func isSupported() -> Bool {
        (try? SMC.keyInfo(key)) != nil
    }
}
