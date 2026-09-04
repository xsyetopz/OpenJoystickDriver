# Haptics backend probe

This isolated Swift package compares macOS controller-output discovery routes
without adding an experimental backend to the shipping application:

- exact SDL HIDAPI-compatible output reports through OJD's `sdl2-3` identity;
- HID PID / Apple Force Feedback service acceptance and device creation;
- public `GCController.haptics` discovery and an optional CoreHaptics pulse.

Build without touching hardware:

```bash
swift build --package-path tools/haptics-backend-probe
```

Run exactly one route, then stop and record physical behavior before running
anything else:

```bash
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try sdl2-3
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try force-feedback
swift run --package-path tools/haptics-backend-probe HapticsBackendProbe try gamecontroller --pulse
```

The `sdl2-3` route publishes OJD's exact `9886:0024` ASTRO identity and Xbox
360 descriptor/report format. SDL2 and SDL3 explicitly select
their Xbox 360 HIDAPI driver for that pair, including its eight-byte rumble
report.

For each run, report application discovery, input shape, rumble motors, trigger
motors, LEDs, disconnect/reconnect, and any crash or disappearance. A positive
HID output size only identifies a raw-report candidate. `FF_OK` proves that the
legacy Force Feedback framework accepts the HID service, while non-nil
`GCController.haptics` proves that Apple's public GameController route exposes
a haptics engine. None of those observations alone prove physical rumble.

Recorded GameSir G7 SE results and the evidence boundaries for each route are
kept in [`docs/testing/haptics-backends.md`](../../docs/testing/haptics-backends.md).
