import Foundation

/// A named power tier expressed as a package watt budget. Frequencies that a
/// budget produces are chip-specific; the budget itself is the portable unit.
public struct Tier: Codable, Sendable {
    public let name: String
    public let watts: Double
    public let summary: String

    public init(name: String, watts: Double, summary: String) {
        self.name = name
        self.watts = watts
        self.summary = summary
    }
}

/// The result of changing a setpoint, so callers can report before/after.
public struct SetResult: Sendable {
    public let key: String
    public let beforeRaw: Int
    public let requestedRaw: Int
    public let afterRaw: Int
    /// True when the value held (read-back equals requested) — the controller
    /// can silently revert writes it doesn't honor.
    public var stuck: Bool { afterRaw == requestedRaw }
}

/// High-level, safe control of the CPU package power tier via AppleCLPC's
/// `pkg-avg-therm-power-target` (the proportional throttle that scales P-core
/// frequency, as opposed to `pkg-low-power-target`'s hard clamp).
public final class PowerController {
    public static let minWatts: Double = 3
    public static let maxWatts: Double = 60

    /// Default tiers, calibrated on an M5 laptop. Treat the frequency hints as
    /// approximate; run `capability` / a sweep to calibrate other chips.
    public static let defaultTiers: [Tier] = [
        Tier(name: "quiet", watts: 5, summary: "deep throttle, coolest/quietest (~3.0 GHz P-core on M5)"),
        Tier(name: "balanced", watts: 8, summary: "moderate cap, good battery (~3.8 GHz P-core on M5)"),
        Tier(name: "high", watts: 12, summary: "near full speed with a ceiling (~full on M5)"),
        Tier(name: "full", watts: -1, summary: "no cap — full turbo (disables the budget)")
    ]

    private let clpc: CLPC

    public init() throws {
        clpc = try CLPC()
    }

    public static var isSupported: Bool {
        CLPC.isAvailable
    }

    /// Whether the therm-target key this tool drives exists on this machine.
    public func isThermTargetPresent() -> Bool {
        clpc.hasProperty(CLPC.thermPowerTargetKey)
    }

    public func currentThermRaw() throws -> Int {
        try clpc.readInt(CLPC.thermPowerTargetKey)
    }

    public func currentLowPowerRaw() throws -> Int {
        try clpc.readInt(CLPC.lowPowerTargetKey)
    }

    /// Set the therm power budget to `watts` (sticky). Reads back to confirm.
    public func setThermWatts(_ watts: Double) throws -> SetResult {
        guard watts >= Self.minWatts, watts <= Self.maxWatts else {
            throw ControllerError.wattsOutOfRange(watts, Self.minWatts, Self.maxWatts)
        }
        return try writeTherm(raw: FixedPoint.rawFromWatts(watts))
    }

    /// Set the therm power budget from a persisted raw Q24 value.
    public func setThermRaw(_ raw: Int) throws -> SetResult {
        if !FixedPoint.isDisabled(raw) {
            let watts = FixedPoint.wattsFromRaw(raw)
            guard watts >= Self.minWatts, watts <= Self.maxWatts else {
                throw ControllerError.wattsOutOfRange(watts, Self.minWatts, Self.maxWatts)
            }
        }
        return try writeTherm(raw: raw)
    }

    /// Disable the therm budget (full turbo).
    public func disableTherm() throws -> SetResult {
        try writeTherm(raw: FixedPoint.disabledSentinel)
    }

    /// Resolve a tier by name and apply it (the `full` tier disables the budget).
    public func applyTier(_ name: String, tiers: [Tier] = defaultTiers) throws -> SetResult {
        guard let tier = tiers.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw ControllerError.unknownTier(name)
        }
        if tier.watts <= 0 {
            return try disableTherm()
        }
        return try setThermWatts(tier.watts)
    }

    private func writeTherm(raw: Int) throws -> SetResult {
        let before = (try? clpc.readInt(CLPC.thermPowerTargetKey)) ?? FixedPoint.disabledSentinel
        try clpc.writeInt(CLPC.thermPowerTargetKey, raw)
        let after = (try? clpc.readInt(CLPC.thermPowerTargetKey)) ?? before
        return SetResult(key: CLPC.thermPowerTargetKey, beforeRaw: before, requestedRaw: raw, afterRaw: after)
    }
}

public enum ControllerError: Error, CustomStringConvertible {
    case wattsOutOfRange(Double, Double, Double)
    case unknownTier(String)

    public var description: String {
        switch self {
        case .wattsOutOfRange(let w, let lo, let hi):
            return String(format: "watts %.2f out of range (%.0f–%.0f)", w, lo, hi)
        case .unknownTier(let name):
            return "unknown tier: \(name)"
        }
    }
}
