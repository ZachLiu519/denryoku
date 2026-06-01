# Denryoku (電力)

Granular CPU power tiers for Apple Silicon Macs — a frequency dial that sits
**between Low Power Mode and full power**, which macOS doesn't expose on its own.

> ⚠️ **Experimental.** This drives an *undocumented* AppleCLPC power-controller
> setpoint. It needs root, every setting is reverted by a reboot, and behavior
> varies by chip. Curves here are calibrated on an **Apple M5 laptop**. Use at
> your own risk and read the [Safety](#safety) section.

## What it does

macOS gives you exactly two CPU power states: default, and Low Power Mode. LPM
slams the P-cores to a hard ~2220 MHz clamp — there's nothing in between.

Denryoku drives `` `pkg-avg-therm-power-target `` on the `AppleCLPC` service: a
**proportional** package power budget (in watts) that scales P-core frequency
*smoothly*, instead of a binary clamp. On an M5 laptop under single-core load:

| budget | P-core freq | vs. Low Power Mode |
|--------|-------------|--------------------|
| 5 W    | ~3.0 GHz    | LPM is a fixed 2.2 GHz clamp |
| 6 W    | ~3.2 GHz    | (no intermediate states) |
| 8 W    | ~3.8 GHz    | |
| 10 W+  | ~full turbo | |

So you get a real dial: quieter and cooler than default, faster than LPM.

## Install

Requires macOS 14+ on Apple Silicon, and the Command Line Tools (or Xcode) for
the `swift` compiler.

### From source

```sh
git clone https://github.com/ZachLiu519/denryoku.git
cd denryoku
swift build -c release
sudo cp .build/release/denryoku /usr/local/bin/
```

### Homebrew (tap)

```sh
brew tap ZachLiu519/tap https://github.com/ZachLiu519/denryoku
brew install ZachLiu519/tap/denryoku
```

See [`Formula/denryoku.rb`](Formula/denryoku.rb).

## Usage

```sh
# Inspect chip, OS, and the current tier (read-only, no sudo)
denryoku status

# Set a tier — sticky until you change it or reboot (needs sudo)
sudo denryoku set 8            # 8 W budget
sudo denryoku set --tier quiet # named tier
sudo denryoku set 6.5          # fractional watts work

# Hand control back to macOS (full turbo)
sudo denryoku off

# List built-in tiers
denryoku tiers

# Generate a capability report (read-only) — please submit yours!
denryoku capability
denryoku capability --json
sudo denryoku capability --write-test   # also probes if writes stick

# Environment check
denryoku doctor
```

It also wraps the public `pmset` knobs as reversible, audit-logged profiles:

```sh
denryoku profiles
sudo denryoku apply balanced
sudo denryoku revert
```

## Compatibility & how you can help

The watt→frequency curve and even *whether the key exists* differ across chips.
The honest way to promise broad support is real data from real machines:

```sh
denryoku capability --json > my-mac.json
```

…then open an issue with that JSON. Every report widens the supported matrix —
especially laptops and M1/M2/M3 SoCs we can't reach on cloud CI (AWS EC2 Mac is
desktop-only and skips several generations).

## Architecture

- **`Sources/DenryokuKit/`** — the core library: `CLPC` (IOKit access + write
  allow-list), `FixedPoint` (Q24 watt encoding), `PowerController` (tiers and
  bounds), `SystemInfo`, `CapabilityReport`, and the ported `Pmset` profile
  logic. Pure and reusable (a future GUI links against this).
- **`Sources/Denryoku/`** — the `denryoku` CLI (ArgumentParser).
- **`Sources/DenryokuSelfTest/`** — dependency-free assertions, run with
  `swift run DenryokuSelfTest` (no XCTest/Xcode required).

## Safety

- **Reversible by design.** Tiers are sticky but a reboot clears everything, and
  `off` restores the macOS default immediately.
- **Write allow-list.** The library refuses to write keys that could change core
  topology (core masks, cluster counts); only power/limit/target setpoints are
  permitted.
- **Read-back verification.** Every set re-reads the value and warns if the
  controller didn't honor it.
- **macOS also drives this setpoint.** `` `pkg-avg-therm-power-target `` is part
  of a *closed-loop* controller, so under sustained thermal load the OS may move
  or reclaim your value. Re-run `status` to check; a value you didn't set means
  the OS is managing it.
- Audit logs for `pmset` profile changes: `~/.local/state/denryoku/audit.jsonl`.

## License

[MIT](LICENSE).
