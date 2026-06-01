import ArgumentParser
import Foundation
import DenryokuKit

// MARK: - Root

struct DenryokuCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "denryoku",
        abstract: "Granular CPU power tiers for Apple Silicon Macs via AppleCLPC.",
        discussion: """
        The headline feature is a proportional CPU power dial driven by the
        `pkg-avg-therm-power-target setpoint: unlike Low Power Mode's hard clamp,
        it scales P-core frequency smoothly with a watt budget. Settings are
        sticky until changed or reboot.

        Tiers and watt->frequency hints are calibrated on an M5 laptop; run
        `capability` (and submit it!) to help map other chips.
        """,
        version: denryokuVersion,
        subcommands: [Status.self, Set.self, Off.self, Tiers.self, Capability.self,
                      Doctor.self, Apply.self, Profiles.self, Revert.self, Watch.self],
        defaultSubcommand: Status.self
    )
}

// MARK: - Helpers

private func printSetResult(_ r: SetResult) {
    print("    was: \(r.beforeRaw)  [\(FixedPoint.describe(r.beforeRaw))]")
    print("    now: \(r.afterRaw)  [\(FixedPoint.describe(r.afterRaw))]")
    if !r.stuck {
        print("    WARNING: value did not stick (controller reverted it). This key may be unsupported here.")
    }
}

private func requireWritable() throws {
    guard PowerController.isSupported else {
        throw ValidationError("AppleCLPC not found — this needs an Apple Silicon Mac.")
    }
    if !isRoot && !Shell.sudoReady {
        throw ValidationError("Changing the tier needs root. Re-run with sudo (e.g. `sudo denryoku ...`).")
    }
}

// MARK: - status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show chip, OS, and the current CPU power tier.")

    func run() throws {
        let sys = SystemInfo.current()
        print("System:")
        print("  chip:    \(sys.chipBrand)")
        print("  model:   \(sys.modelIdentifier)")
        print("  macOS:   \(sys.macOSVersion)")
        print("  cores:   \(sys.performanceCores)P + \(sys.efficiencyCores)E (\(sys.totalCPUCores) total)")
        print("")

        guard PowerController.isSupported, let controller = try? PowerController() else {
            print("CPU tier: AppleCLPC unavailable (not supported on this machine).")
            return
        }
        print("CPU tier (`pkg-avg-therm-power-target):")
        if let raw = try? controller.currentThermRaw() {
            print("  therm target:     \(raw)  [\(FixedPoint.describe(raw))]")
        } else {
            print("  therm target:     not present on this machine")
        }
        if let low = try? controller.currentLowPowerRaw() {
            print("  low-power target: \(low)  [\(FixedPoint.describe(low))]")
        }
    }
}

// MARK: - set

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set the CPU power tier (sticky until changed or reboot).",
        discussion: "Provide a watt budget (e.g. `set 8`) or a named tier (`set --tier balanced`)."
    )

    @Argument(help: "Package power budget in watts (\(Int(PowerController.minWatts))–\(Int(PowerController.maxWatts))).")
    var watts: Double?

    @Option(name: .shortAndLong, help: "Named tier instead of raw watts (see `tiers`).")
    var tier: String?

    func validate() throws {
        if watts == nil && tier == nil {
            throw ValidationError("Provide a watt value (e.g. `set 8`) or --tier <name>.")
        }
        if watts != nil && tier != nil {
            throw ValidationError("Provide either watts or --tier, not both.")
        }
    }

    func run() throws {
        try requireWritable()
        let controller = try PowerController()
        let result: SetResult
        if let tier {
            result = try controller.applyTier(tier)
            print("Set tier '\(tier)':")
        } else {
            result = try controller.setThermWatts(watts!)
            print("Set CPU budget to \(watts!) W:")
        }
        printSetResult(result)
        print("\nSticky until changed or reboot. Revert with: denryoku off")
    }
}

// MARK: - off

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Disable the CPU power cap (full turbo).")

    func run() throws {
        try requireWritable()
        let controller = try PowerController()
        let result = try controller.disableTherm()
        print("Disabled CPU budget (full turbo):")
        printSetResult(result)
    }
}

// MARK: - tiers

struct Tiers: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the built-in power tiers.")

    func run() {
        print("Built-in tiers (watt budgets; frequency hints calibrated on M5):\n")
        for tier in PowerController.defaultTiers {
            let watts = tier.watts <= 0 ? "off" : "\(Int(tier.watts))W"
            print("  \(tier.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(watts.padding(toLength: 5, withPad: " ", startingAt: 0)) \(tier.summary)")
        }
        print("\nApply with: denryoku set --tier <name>")
    }
}

// MARK: - capability

struct Capability: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a capability report for this Mac (read-only by default).",
        discussion: "Submit reports to help map support across chips. --write-test (needs root) probes whether a small write sticks."
    )

    @Flag(help: "Emit JSON instead of a human summary.")
    var json = false

    @Flag(help: "Also run a guarded, self-restoring write-stick test (requires root).")
    var writeTest = false

    func run() throws {
        if writeTest && !isRoot && !Shell.sudoReady {
            throw ValidationError("--write-test needs root. Re-run with sudo.")
        }
        let report = CapabilityReport.generate(runWriteTest: writeTest)
        if json {
            print(report.jsonString())
            return
        }
        let s = report.system
        print("denryoku capability report (v\(report.toolVersion))")
        print("  chip:                 \(s.chipBrand)")
        print("  model:                \(s.modelIdentifier)")
        print("  macOS:                \(s.macOSVersion)")
        print("  cores:                \(s.performanceCores)P + \(s.efficiencyCores)E")
        print("  AppleCLPC available:  \(report.clpcAvailable)")
        print("  therm target present: \(report.thermTargetPresent)")
        if let w = report.thermTargetWatts, let raw = report.thermTargetRaw {
            print("  therm target value:   \(raw) [\(FixedPoint.describe(raw))] (\(String(format: "%.2f", w)) W)")
        }
        print("  low-power present:    \(report.lowPowerTargetPresent)")
        if let t = report.writeTest {
            print("  write-stick test:     \(t.stuck ? "STUCK (controllable)" : "reverted (not honored)")")
        }
        print("\nFull JSON: denryoku capability --json")
    }
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the environment and required tools.")

    func run() {
        print("Tooling:")
        for cmd in ["pmset", "powermetrics", "ioreg", "sysctl"] {
            print("  \(cmd): \(Shell.env(["which", cmd]).ok ? "ok" : "missing")")
        }
        print("\nCapabilities:")
        print("  AppleCLPC:        \(CLPC.isAvailable ? "available" : "missing")")
        print("  running as root:  \(isRoot)")
        print("  sudo (no prompt): \(Shell.sudoReady)")
        print("\nProfiles:")
        if let profiles = try? Pmset.loadProfiles() {
            print("  loaded \(profiles.count) pmset profiles from \(Pmset.profilesURL().path)")
        } else {
            print("  no profiles.json found (pmset profile commands will be unavailable)")
        }
    }
}

// MARK: - pmset profile commands (ported)

struct Apply: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Apply a pmset profile (macOS public power knobs).")

    @Argument(help: "Profile name (see `profiles`).")
    var profile: String

    @Flag(help: "Allow applying profiles marked experimental.")
    var experimental = false

    func run() throws {
        let state = try Pmset.apply(profileName: profile, allowExperimental: experimental)
        print("Applied profile '\(profile)'. Measured pmset state:")
        print(state)
    }
}

struct Profiles: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List configured pmset profiles.")

    func run() throws {
        for profile in try Pmset.loadProfiles() {
            print("\(profile.name) [\(profile.experimental ? "experimental" : "supported")]")
            print("  \(profile.description)")
            if let lp = profile.controls.lowPowerMode { print("  lowPowerMode: \(lp ? "on" : "off")") }
        }
    }
}

struct Revert: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Revert the last applied pmset profile.")

    func run() throws {
        print(try Pmset.revert())
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Repeatedly print status.")

    @Option(help: "Seconds between samples.")
    var interval: Double = 5

    func run() {
        while true {
            print("=== \(ISO8601DateFormatter().string(from: Date())) ===")
            try? Status().run()
            print("")
            fflush(stdout)
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

DenryokuCLI.main()
