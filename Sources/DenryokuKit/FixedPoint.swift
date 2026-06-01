import Foundation

/// AppleCLPC encodes its package power setpoints (`pkg-low-power-target`,
/// `pkg-avg-therm-power-target`) as signed Q24 fixed-point watts: the raw
/// integer is watts * 2^24. A raw value of -2^24 (-1.0 W) is the "disabled"
/// sentinel meaning "no budget / full turbo".
public enum FixedPoint {
    /// 2^24 — the raw value that represents 1.0 W in Q24.
    public static let q24: Int = 16_777_216

    /// The disabled sentinel (-1.0 W) the controller uses to mean "no limit".
    public static let disabledSentinel: Int = -16_777_216

    /// Encode watts into the raw Q24 integer the controller expects.
    public static func rawFromWatts(_ watts: Double) -> Int {
        Int((watts * Double(q24)).rounded())
    }

    /// Decode a raw Q24 integer back into watts.
    public static func wattsFromRaw(_ raw: Int) -> Double {
        Double(raw) / Double(q24)
    }

    /// True when a raw value is the disabled sentinel (or any non-positive
    /// budget, which the controller treats as "unrestricted").
    public static func isDisabled(_ raw: Int) -> Bool {
        raw <= 0
    }

    /// Human-readable description of a raw setpoint value.
    public static func describe(_ raw: Int) -> String {
        if raw == disabledSentinel {
            return "disabled (full turbo)"
        }
        if isDisabled(raw) {
            return String(format: "%.2f W (non-positive -> unrestricted)", wattsFromRaw(raw))
        }
        return String(format: "%.2f W budget", wattsFromRaw(raw))
    }
}
