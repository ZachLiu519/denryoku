import Foundation

/// Result of running an external process.
public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var ok: Bool { status == 0 }
}

public enum Shell {
    public static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(status: 127, stdout: "", stderr: "\(error)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run a command via `/usr/bin/env`, resolving it on PATH.
    public static func env(_ arguments: [String]) -> CommandResult {
        run("/usr/bin/env", arguments)
    }

    /// True when non-interactive sudo is currently usable.
    public static var sudoReady: Bool {
        env(["sudo", "-n", "true"]).ok
    }
}

/// Whether the current process is running as root.
public var isRoot: Bool {
    getuid() == 0
}
