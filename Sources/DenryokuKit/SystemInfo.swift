import Foundation

/// A snapshot of the host's identity, used for capability reporting and for
/// deciding whether a tier curve is trustworthy on this hardware.
public struct SystemInfo: Codable, Sendable {
    public let chipBrand: String
    public let modelIdentifier: String
    public let macOSVersion: String
    public let totalCPUCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let isAppleSilicon: Bool

    public static func current() -> SystemInfo {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "unknown"
        let model = sysctlString("hw.model") ?? "unknown"
        let pCores = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
        let eCores = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        let total = sysctlInt("hw.physicalcpu") ?? (pCores + eCores)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let isArm = brand.lowercased().contains("apple")

        return SystemInfo(
            chipBrand: brand,
            modelIdentifier: model,
            macOSVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            totalCPUCores: total,
            performanceCores: pCores,
            efficiencyCores: eCores,
            isAppleSilicon: isArm
        )
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
