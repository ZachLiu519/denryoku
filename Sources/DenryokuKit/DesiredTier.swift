import Foundation

/// The user's requested CLPC target, persisted so a root wake daemon can
/// reapply it after AppleCLPC's private enforcement state is rebuilt.
public struct DesiredTierState: Codable, Sendable {
    public let raw: Int
    public let label: String
    public let updatedAt: String

    public init(raw: Int, label: String, updatedAt: String) {
        self.raw = raw
        self.label = label
        self.updatedAt = updatedAt
    }

    public var isDisabled: Bool {
        FixedPoint.isDisabled(raw)
    }
}

public enum DesiredTierStore {
    public static let defaultURL = URL(fileURLWithPath: "/Library/Application Support/Denryoku/desired-tier.json")

    public static func makeState(raw: Int, label: String, date: Date = Date()) -> DesiredTierState {
        DesiredTierState(raw: raw, label: label, updatedAt: ISO8601DateFormatter().string(from: date))
    }

    public static func load(from url: URL = defaultURL) throws -> DesiredTierState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DesiredTierState.self, from: data)
    }

    public static func save(_ state: DesiredTierState, to url: URL = defaultURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes([
            .posixPermissions: 0o755,
            .ownerAccountID: 0,
            .groupOwnerAccountID: 0
        ], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([
            .posixPermissions: 0o644,
            .ownerAccountID: 0,
            .groupOwnerAccountID: 0
        ], ofItemAtPath: url.path)
    }
}
