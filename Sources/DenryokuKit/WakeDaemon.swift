import Dispatch
import Foundation
import IOKit
import IOKit.pwr_mgt

public enum WakeDaemonError: Error, CustomStringConvertible {
    case noSavedTarget
    case registrationFailed

    public var description: String {
        switch self {
        case .noSavedTarget:
            return "No saved CPU tier found. Run `sudo denryoku set <watts>` first."
        case .registrationFailed:
            return "Could not register for system power notifications."
        }
    }
}

public enum WakeDaemon {
    public static let label = "com.zachliu.denryoku.wake"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    public static let helperPath = "/Library/PrivilegedHelperTools/denryoku"
    public static let logPath = "/var/log/denryoku-wake.log"
    public static let retryDelays: [TimeInterval] = [2, 5, 15, 30]
    static let canSystemSleepMessage: UInt32 = 0xE0000270
    static let systemWillSleepMessage: UInt32 = 0xE0000280
    static let systemHasPoweredOnMessage: UInt32 = 0xE0000300

    public static func plistData(executablePath: String) -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public static func plist(executablePath: String) -> String {
        String(data: plistData(executablePath: executablePath), encoding: .utf8) ?? ""
    }

    @discardableResult
    public static func reapplySavedTarget(force: Bool = true) throws -> SetResult {
        guard let state = try DesiredTierStore.load() else {
            throw WakeDaemonError.noSavedTarget
        }
        let controller = try PowerController()
        if force && !state.isDisabled {
            _ = try controller.setThermRaw(FixedPoint.disabledSentinel)
            Thread.sleep(forTimeInterval: 0.25)
        }
        return try controller.setThermRaw(state.raw)
    }

    static func logReapply(_ reason: String) {
        do {
            let result = try reapplySavedTarget()
            log("\(reason): reapplied \(FixedPoint.describe(result.afterRaw))")
        } catch {
            log("\(reason): reapply failed: \(error)")
        }
    }

    static func log(_ message: String) {
        print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
        fflush(stdout)
    }
}

public final class WakeDaemonRunner: @unchecked Sendable {
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let retryQueue = DispatchQueue(label: "com.zachliu.denryoku.wake.retry")
    private var retryGeneration = 0

    public init() {}

    deinit {
        if notifier != 0 {
            IOObjectRelease(notifier)
        }
        if rootPort != 0 {
            IOServiceClose(rootPort)
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
    }

    public func run() throws -> Never {
        var port: IONotificationPortRef?
        var object: io_object_t = 0
        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &port,
            { refcon, _, messageType, messageArgument in
                guard let refcon else { return }
                let runner = Unmanaged<WakeDaemonRunner>.fromOpaque(refcon).takeUnretainedValue()
                runner.handlePowerMessage(messageType, argument: messageArgument)
            },
            &object
        )
        guard rootPort != 0, let port else {
            throw WakeDaemonError.registrationFailed
        }
        notifyPort = port
        notifier = object

        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        WakeDaemon.log("starting")
        WakeDaemon.logReapply("startup")
        CFRunLoopRun()
        fatalError("CFRunLoopRun returned unexpectedly")
    }

    private func handlePowerMessage(_ messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case WakeDaemon.canSystemSleepMessage, WakeDaemon.systemWillSleepMessage:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case WakeDaemon.systemHasPoweredOnMessage:
            retryQueue.async {
                self.retryGeneration += 1
                self.scheduleWakeRetry(at: 0, generation: self.retryGeneration)
            }
        default:
            break
        }
    }

    private func scheduleWakeRetry(at index: Int, generation: Int) {
        guard index < WakeDaemon.retryDelays.count else { return }
        retryQueue.asyncAfter(deadline: .now() + WakeDaemon.retryDelays[index]) {
            guard generation == self.retryGeneration else { return }
            do {
                let result = try WakeDaemon.reapplySavedTarget()
                if result.stuck {
                    WakeDaemon.log("wake: reapplied \(FixedPoint.describe(result.afterRaw))")
                } else {
                    WakeDaemon.log("wake: controller did not hold \(FixedPoint.describe(result.requestedRaw)); retrying")
                    self.scheduleWakeRetry(at: index + 1, generation: generation)
                }
            } catch {
                WakeDaemon.log("wake: reapply failed: \(error); retrying")
                self.scheduleWakeRetry(at: index + 1, generation: generation)
            }
        }
    }
}
