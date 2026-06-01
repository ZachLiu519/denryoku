import Foundation

public struct ProfileFile: Codable, Sendable {
    public let profiles: [Profile]
}

public struct Profile: Codable, Sendable {
    public let name: String
    public let description: String
    public let controls: ProfileControls
    public let targets: [String: String]
    public let experimental: Bool
}

public struct ProfileControls: Codable, Sendable {
    public let lowPowerMode: Bool?
    public let displaySleepMinutes: Int?
    public let systemSleepMinutes: Int?
    public let diskSleepMinutes: Int?
    public let processPolicy: String?
}

public struct AuditEntry: Codable, Sendable {
    public let timestamp: String
    public let profile: String
    public let command: String
    public let previousPmset: [String: [String: String]]
    public let requestedControls: ProfileControls
    public let afterPmset: [String: [String: String]]
}

public enum PmsetError: Error, CustomStringConvertible {
    case missingProfile(String)
    case profileFileMissing(URL)
    case commandFailed(String)
    case sudoUnavailable
    case experimental(String)

    public var description: String {
        switch self {
        case .missingProfile(let name): return "Profile not found: \(name)"
        case .profileFileMissing(let url): return "Could not find profiles file at \(url.path)"
        case .commandFailed(let message): return message
        case .sudoUnavailable:
            return "Changing power settings needs sudo. Authenticate with `sudo -v`, or run as root."
        case .experimental(let name):
            return "Profile '\(name)' is experimental. Re-run with --experimental to apply it."
        }
    }
}

/// Reversible, audit-logged pmset profile control (ported from the original
/// CLI). This drives macOS's public power knobs — distinct from the CLPC tier.
public enum Pmset {
    public static func parseCustom(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasSuffix("Power:") {
                let name = String(line.dropLast())
                sections[name] = [:]
                current = name
                continue
            }
            guard let section = current else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let key = parts.dropLast().joined(separator: " ")
            sections[section]?[key] = String(parts.last ?? "")
        }
        return sections
    }

    public static func currentCustom() -> [String: [String: String]] {
        parseCustom(Shell.env(["pmset", "-g", "custom"]).stdout)
    }

    public static func profilesURL() -> URL {
        let fm = FileManager.default
        let candidates = profileCandidates()
        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
            ?? URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("profiles.json")
    }

    static func profileCandidates() -> [URL] {
        var candidates = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("profiles.json")]
        if let executable = Bundle.main.executableURL {
            var dir = executable.deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(dir.appendingPathComponent("profiles.json"))
                dir.deleteLastPathComponent()
            }
        }
        return candidates
    }

    public static func loadProfiles() throws -> [Profile] {
        let url = profilesURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PmsetError.profileFileMissing(url)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProfileFile.self, from: data).profiles
    }

    static func auditURL() throws -> URL {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/denryoku")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audit.jsonl")
    }

    static func appendAudit(_ entry: AuditEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        let url = try auditURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    static func readLastAudit() throws -> AuditEntry? {
        let url = try auditURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url)
        guard let last = text.split(separator: "\n").last else { return nil }
        return try JSONDecoder().decode(AuditEntry.self, from: Data(last.utf8))
    }

    static func isoTimestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    static func requireSudoReady() throws {
        guard Shell.sudoReady else { throw PmsetError.sudoUnavailable }
    }

    static func set(_ key: String, _ value: String) throws {
        let result = Shell.env(["sudo", "-n", "pmset", "-a", key, value])
        guard result.ok else {
            throw PmsetError.commandFailed("pmset \(key) failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }
    }

    public static func apply(profileName: String, allowExperimental: Bool) throws -> String {
        let profiles = try loadProfiles()
        guard let profile = profiles.first(where: { $0.name == profileName }) else {
            throw PmsetError.missingProfile(profileName)
        }
        if profile.experimental && !allowExperimental {
            throw PmsetError.experimental(profile.name)
        }

        let before = currentCustom()
        try requireSudoReady()
        try appendAudit(AuditEntry(
            timestamp: isoTimestamp(), profile: profile.name,
            command: "preflight rollback for " + CommandLine.arguments.joined(separator: " "),
            previousPmset: before, requestedControls: profile.controls, afterPmset: before))

        if let lowPower = profile.controls.lowPowerMode { try set("lowpowermode", lowPower ? "1" : "0") }
        if let v = profile.controls.displaySleepMinutes { try set("displaysleep", String(v)) }
        if let v = profile.controls.systemSleepMinutes { try set("sleep", String(v)) }
        if let v = profile.controls.diskSleepMinutes { try set("disksleep", String(v)) }

        let after = currentCustom()
        try appendAudit(AuditEntry(
            timestamp: isoTimestamp(), profile: profile.name,
            command: CommandLine.arguments.joined(separator: " "),
            previousPmset: before, requestedControls: profile.controls, afterPmset: after))

        return Shell.env(["pmset", "-g", "custom"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func restoreKey(_ key: String, from state: [String: [String: String]]) throws {
        let battery = state["Battery Power"]?[key]
        let ac = state["AC Power"]?[key]
        if battery == ac, let value = battery { try set(key, value); return }
        if let battery {
            let r = Shell.env(["sudo", "-n", "pmset", "-b", key, battery])
            guard r.ok else { throw PmsetError.commandFailed("pmset -b \(key) failed") }
        }
        if let ac {
            let r = Shell.env(["sudo", "-n", "pmset", "-c", key, ac])
            guard r.ok else { throw PmsetError.commandFailed("pmset -c \(key) failed") }
        }
    }

    public static func revert() throws -> String {
        guard let entry = try readLastAudit() else { return "No audit entry found; nothing to revert." }
        try requireSudoReady()
        for key in ["lowpowermode", "displaysleep", "sleep", "disksleep"] {
            try restoreKey(key, from: entry.previousPmset)
        }
        return "Reverted pmset controls from audit entry at \(entry.timestamp)."
    }
}
