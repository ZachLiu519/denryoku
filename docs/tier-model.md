# Tier Model

Profiles are declarative requests. The tool records what it asked macOS to do,
then reports the measured state after the request. That distinction matters
because Apple Silicon frequency and power policy can be overridden by macOS,
thermal state, workload QoS, and private SoC controllers.

## Profile Fields

- `name`: stable identifier used by `denryoku apply <name>`.
- `description`: human-readable purpose.
- `controls`: supported or best-effort actions the tool can request.
- `targets`: desired CPU/GPU/noise behavior, used for reporting and future policy backends.
- `experimental`: requires `--experimental` when the profile may rely on unproven behavior.

## Control Levels

- `lowPowerMode`: supported coarse control through `pmset lowpowermode`.
- `displaySleepMinutes`, `systemSleepMinutes`, `diskSleepMinutes`: supported `pmset` timers.
- `processPolicy`: declared scheduling intent. Process changes require explicit PIDs or app names so the tool does not silently throttle user work.

## Honesty Rule

Every tier must expose both:

- Requested state: the controls and targets in `profiles.json`.
- Measured state: current `pmset`, thermal state, and available telemetry from the research probes.

If macOS ignores a request or a direct CPU/GPU cap cannot be proven, the profile remains useful as a transparent best-effort policy instead of pretending to control hardware it cannot control.

