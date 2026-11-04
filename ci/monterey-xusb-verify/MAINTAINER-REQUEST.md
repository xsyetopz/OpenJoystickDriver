# Maintainer request: signed tester build for Xbox 360 absolute observation

## Summary
Wired Xbox 360 / XUSB clones (`045E:028E`, including common Chinese pads that
spoof Microsoft IDs) send complete 20-byte snapshots. `Xbox360Parser` previously
emitted edge deltas only and did not implement `ControllerInputReportObserver`.

After `DevicePipeline` resets observed state (suspend/resume) without clearing
parser `prev*` fields, held face buttons stop producing edges. Live Monterey
Intel observation: RX bits change (`00 14 00 10` / `00 40` / `00 60`) while
`controller state` stays `pressedButtons=[]` with stick rest from `0xFFFF`
(≈ `-3e-05`). PR #24 xpad bit mapping is already correct — this is not a remap.

## Fix (minimal)
Make `Xbox360Parser` conform to `ControllerInputReportObserver` and publish an
absolute control snapshot each validated wired report (same contract as DS4).
Pipeline already reconciles `latestInputReportObservation` into
`currentInputState`.

Files:
- `Sources/OpenJoystickDriverKit/Protocol/Parsers/Xbox360Parser.swift`
- `Tests/OpenJoystickDriverKitTests/Protocol/Parsers/Xbox360ParserTests.swift`
  (fixtures from real Monterey `045E:028E` captures)

Patch artifact: `0001-xbox360-absolute-observation.patch`

## Why a signed tester build is required
Virtual gamepad output needs `com.apple.developer.hid.virtual.device` on the
host app. Ad-hoc / contributor builds cannot honestly retain that restricted
entitlement (see `docs/development/signing.md` and prior tester comments on
PR #27). The reporter only has an Intel MacBook Pro 2015 on macOS Monterey 12
and cannot run Swift 6.3 locally.

## Ask
1. Please review/merge the absolute-observation patch (or apply the attached patch
   onto `0.5.0-beta.4` / current main).
2. Please publish a **maintainer-signed, notarized tester DMG**
   (`just package-tester`) that includes the fix.
3. Hardware verification target after install:
   - Close Steam so OJD can claim interface 0.
   - `compat set sdl2-3` (Xbox 360 family → Microsoft `045E:028E` virtual HID).
   - Confirm `controller watch` shows face buttons while pressing.
   - Confirm native GeForce NOW sees the virtual pad.

## CI already run (when available)
GitHub Actions workflow `Monterey XUSB verify` on `macos-26-intel`:
- Swift ≥ 6.3 toolchain gate
- `swift test --filter Xbox360ParserTests`
- `swift build -c release --arch x86_64 --product OpenJoystickDriverKit`
  with `MACOSX_DEPLOYMENT_TARGET=12.0`
- Artifacts: test log, build log, patch, signing assessment

CI success proves the parser fix; it does **not** prove Virtual HID / GFN on
Monterey until a signed app is installed on hardware.
