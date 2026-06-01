import Foundation
import IOKit

/// Errors surfaced by the CLPC access layer.
public enum CLPCError: Error, CustomStringConvertible {
    case serviceMissing
    case propertyMissing(String)
    case unsafeKey(String)
    case writeFailed(key: String, code: kern_return_t)
    case notRoot

    public var description: String {
        switch self {
        case .serviceMissing:
            return "AppleCLPC service was not found (is this an Apple Silicon Mac?)"
        case .propertyMissing(let key):
            return "AppleCLPC property not found: \(key)"
        case .unsafeKey(let key):
            return "Refusing to write a key not on the safe allow-list: \(key)"
        case .writeFailed(let key, let code):
            return "Writing \(key) failed (kern_return_t \(code)). Are you running as root?"
        case .notRoot:
            return "Changing power settings requires root. Re-run with sudo."
        }
    }
}

/// Thin, safe wrapper over the `AppleCLPC` IORegistry service.
///
/// Reads are unprivileged; writes require root. A write allow-list prevents
/// poking keys that could wedge the machine (core masks, cluster counts, …).
public final class CLPC {
    /// Power setpoint keys we know how to drive. The leading backtick is part
    /// of the actual IORegistry key name.
    public static let thermPowerTargetKey = "`pkg-avg-therm-power-target"
    public static let lowPowerTargetKey = "`pkg-low-power-target"

    private let service: io_registry_entry_t

    public init() throws {
        guard let matching = IOServiceMatching("AppleCLPC") else {
            throw CLPCError.serviceMissing
        }
        let handle = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard handle != 0 else {
            throw CLPCError.serviceMissing
        }
        service = handle
    }

    deinit {
        IOObjectRelease(service)
    }

    public static var isAvailable: Bool {
        guard let matching = IOServiceMatching("AppleCLPC") else { return false }
        let handle = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard handle != 0 else { return false }
        IOObjectRelease(handle)
        return true
    }

    /// All properties exposed by the service.
    public func allProperties() throws -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = unmanaged?.takeRetainedValue() as NSDictionary? else {
            throw CLPCError.serviceMissing
        }
        var out: [String: Any] = [:]
        for (key, value) in dict {
            if let key = key as? String { out[key] = value }
        }
        return out
    }

    /// Whether a key currently exists on the service.
    public func hasProperty(_ key: String) -> Bool {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return false }
        _ = value
        return true
    }

    /// Read a key as a signed 64-bit integer (CLPC values are stored unsigned;
    /// we reinterpret so sentinels like -16777216 read back correctly).
    public func readInt(_ key: String) throws -> Int {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else {
            throw CLPCError.propertyMissing(key)
        }
        guard let number = value as? NSNumber else {
            throw CLPCError.propertyMissing(key)
        }
        return Int(Int64(bitPattern: number.uint64Value))
    }

    /// Write a signed integer to a key. Guarded by the safe-key allow-list.
    @discardableResult
    public func writeInt(_ key: String, _ value: Int) throws -> kern_return_t {
        guard CLPC.isSafeToWrite(key) else {
            throw CLPCError.unsafeKey(key)
        }
        let result = IORegistryEntrySetCFProperty(service, key as CFString, NSNumber(value: value))
        guard result == KERN_SUCCESS else {
            throw CLPCError.writeFailed(key: key, code: result)
        }
        return result
    }

    /// Conservative allow-list for writes. We permit the known package power
    /// setpoints and obvious power/limit/target tunables, and hard-block
    /// anything that could change core topology.
    public static func isSafeToWrite(_ key: String) -> Bool {
        let lower = key.lowercased()
        if lower.contains("core-mask") || lower.contains("num-cores")
            || lower.contains("num-clusters") || lower.contains("cluster-mask") {
            return false
        }
        if key == thermPowerTargetKey || key == lowPowerTargetKey {
            return true
        }
        return lower.contains("power") || lower.contains("target")
            || lower.contains("limit") || lower.contains("thresh")
    }
}
