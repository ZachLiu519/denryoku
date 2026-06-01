import Foundation

/// The tool's semantic version, surfaced in reports and `--version`.
public let denryokuVersion = "0.1.0"

/// Result of a guarded write-stick test (only run with `--write-test`, requires
/// root). We write a value, read it back, then restore the original.
public struct WriteStickTest: Codable, Sendable {
    public let requestedRaw: Int
    public let afterWriteRaw: Int
    public let stuck: Bool
    public let restoredRaw: Int
}

/// A self-contained, submittable capability report. Read-only by default; the
/// optional write test is the only part that mutates (and self-restores).
public struct CapabilityReport: Codable, Sendable {
    public let toolVersion: String
    public let generatedAt: String
    public let system: SystemInfo
    public let clpcAvailable: Bool
    public let thermTargetPresent: Bool
    public let lowPowerTargetPresent: Bool
    public let thermTargetRaw: Int?
    public let thermTargetWatts: Double?
    public let lowPowerTargetRaw: Int?
    public let writeTest: WriteStickTest?

    /// Build a report. Pass `runWriteTest: true` (requires root) to additionally
    /// probe whether a small therm-target write sticks on this hardware.
    public static func generate(runWriteTest: Bool = false, testWatts: Double = 8) -> CapabilityReport {
        let system = SystemInfo.current()
        let clpcAvailable = CLPC.isAvailable

        var thermPresent = false
        var lowPresent = false
        var thermRaw: Int?
        var lowRaw: Int?
        var writeTest: WriteStickTest?

        if clpcAvailable, let clpc = try? CLPC() {
            thermPresent = clpc.hasProperty(CLPC.thermPowerTargetKey)
            lowPresent = clpc.hasProperty(CLPC.lowPowerTargetKey)
            thermRaw = try? clpc.readInt(CLPC.thermPowerTargetKey)
            lowRaw = try? clpc.readInt(CLPC.lowPowerTargetKey)

            if runWriteTest, thermPresent, let original = thermRaw {
                let requested = FixedPoint.rawFromWatts(testWatts)
                let afterWrite = (try? clpc.writeInt(CLPC.thermPowerTargetKey, requested))
                    .flatMap { _ in try? clpc.readInt(CLPC.thermPowerTargetKey) } ?? original
                try? clpc.writeInt(CLPC.thermPowerTargetKey, original)
                let restored = (try? clpc.readInt(CLPC.thermPowerTargetKey)) ?? original
                writeTest = WriteStickTest(
                    requestedRaw: requested,
                    afterWriteRaw: afterWrite,
                    stuck: afterWrite == requested,
                    restoredRaw: restored
                )
            }
        }

        return CapabilityReport(
            toolVersion: denryokuVersion,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            system: system,
            clpcAvailable: clpcAvailable,
            thermTargetPresent: thermPresent,
            lowPowerTargetPresent: lowPresent,
            thermTargetRaw: thermRaw,
            thermTargetWatts: thermRaw.map(FixedPoint.wattsFromRaw),
            lowPowerTargetRaw: lowRaw,
            writeTest: writeTest
        )
    }

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}
