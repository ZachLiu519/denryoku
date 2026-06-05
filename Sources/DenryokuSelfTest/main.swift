import Foundation
import DenryokuKit

func runSelfTest() -> Int {
    var failures = 0
    func check(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok: \(label)")
        } else {
            failures += 1
            print("  FAIL: \(label)")
        }
    }

    print("FixedPoint:")
    check(FixedPoint.rawFromWatts(1.0) == FixedPoint.q24, "1.0W == q24")
    check(FixedPoint.rawFromWatts(8.0) == 8 * FixedPoint.q24, "8.0W == 8*q24")
    check(abs(FixedPoint.wattsFromRaw(FixedPoint.q24) - 1.0) < 0.0001, "q24 decodes to 1.0W")
    check(abs(FixedPoint.wattsFromRaw(83_886_080) - 5.0) < 0.0001, "83886080 decodes to 5.0W")
    check(FixedPoint.disabledSentinel == -16_777_216, "sentinel is -16777216")
    check(FixedPoint.isDisabled(FixedPoint.disabledSentinel), "sentinel is disabled")
    check(FixedPoint.isDisabled(0), "0 is disabled")
    check(!FixedPoint.isDisabled(FixedPoint.q24), "1W is not disabled")
    check(FixedPoint.describe(FixedPoint.disabledSentinel) == "disabled (full turbo)", "describe sentinel")
    check(FixedPoint.describe(8 * FixedPoint.q24).contains("8.00 W"), "describe 8W")

    print("CLPC allow-list:")
    check(CLPC.isSafeToWrite(CLPC.thermPowerTargetKey), "therm key is writable")
    check(CLPC.isSafeToWrite(CLPC.lowPowerTargetKey), "low-power key is writable")
    check(!CLPC.isSafeToWrite("#cpu-core-mask"), "core-mask blocked")
    check(!CLPC.isSafeToWrite("#cpu-num-clusters"), "num-clusters blocked")

    print("Desired tier persistence:")
    let saved = DesiredTierState(raw: FixedPoint.rawFromWatts(9), label: "9.00 W", updatedAt: "2026-06-05T00:00:00Z")
    let encoded = try! JSONEncoder().encode(saved)
    let decoded = try! JSONDecoder().decode(DesiredTierState.self, from: encoded)
    check(decoded.raw == FixedPoint.rawFromWatts(9), "saved state preserves raw target")
    check(decoded.label == "9.00 W", "saved state preserves label")
    check(decoded.isDisabled == false, "positive saved state is enabled")
    check(DesiredTierState(raw: FixedPoint.disabledSentinel, label: "off", updatedAt: "now").isDisabled, "sentinel saved state is disabled")

    print("LaunchDaemon plist:")
    let plist = WakeDaemon.plist(executablePath: "/usr/local/bin/denryoku & helper")
    check(plist.contains("<string>/usr/local/bin/denryoku &amp; helper</string>"), "plist XML-escapes executable")
    check(plist.contains("<string>daemon</string>"), "plist starts daemon command")
    check(plist.contains("<key>KeepAlive</key>"), "plist keeps wake daemon alive")
    let plistData = WakeDaemon.plistData(executablePath: "/usr/local/bin/denryoku")
    let parsed = try! PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
    check(parsed["Label"] as? String == WakeDaemon.label, "plist has daemon label")
    check((parsed["ProgramArguments"] as? [String]) == ["/usr/local/bin/denryoku", "daemon"], "plist has daemon arguments")
    check(WakeDaemon.helperPath == "/Library/PrivilegedHelperTools/denryoku", "daemon uses privileged helper path")
    check(WakeDaemon.retryDelays == [2, 5, 15, 30], "daemon retry delays are bounded")

    print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
    return failures
}

exit(runSelfTest() == 0 ? 0 : 1)
