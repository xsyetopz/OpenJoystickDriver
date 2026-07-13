# Changelog

All notable changes to OpenJoystickDriver are documented in this file.

## 0.5.0-alpha.5

### Added

- Added an authenticated, user-private local RPC endpoint so headless commands can
  reach the running main application without a helper process.
- Added application-service health, log, permission, and virtual-output
  diagnostics with bounded subprocess and report handling.
- Added a deterministic controller-record catalog generated from pinned Linux
  kernel sources, with strict schemas, provenance, reviewable per-device output,
  and explicit local add/patch overrides.
- Added live USB interface, alternate-setting, and interrupt-endpoint discovery
  through SwiftUSB, plus device-provided product names with numeric VID/PID
  fallback text.
- Added focused validation for malformed records, duplicate identities,
  conflicting or orphaned overrides, redundant defaults, and descriptor
  selection failures.

### Changed

- Consolidated controller processing and background service ownership into the
  persistent main application, removing the embedded daemon, LaunchAgent, XPC
  protocol, and second privacy identity.
- Registered the main application itself as the login item and made it the sole
  owner of Input Monitoring and Accessibility requests.
- Split the DriverKit relay implementation into focused lifecycle, connection,
  report, and device-description components.
- Removed browser Gamepad capture, runtime soak, and private Apple catalog audit
  controls from the menu app while retaining their headless diagnostic commands
  and the focused support-report workflow.
- Limited the private Apple GameController catalog audit to exact physical OJD
  record evidence; live `GCController.supportsHIDDevice` and hardware behavior
  remain authoritative for virtual compatibility identities.
- Reorganized repository scripts by ownership, replaced legacy environment
  fragments with the single root environment contract, and strengthened script
  and Swift-structure validation.
- Replaced all earlier controller and device configuration formats with the
  canonical `Controllers/<vid>/<vid>-<pid>.json` record format.
- Moved shared endpoints, startup sequences, timeouts, packet behavior, and
  output policy out of controller records and into protocol implementations.
- Updated the runtime to SwiftUSB 0.1.1 and removed OpenJoystickDriver-specific
  libusb descriptor shims and extra USB contexts.

### Fixed

- Corrected permission status to use authoritative access checks from the main
  application and removed the obsolete helper-selection workflow.
- Made virtual-device self-test exit status follow the required DriverKit and
  user-space relay verdicts.
- Added bounded compatibility-device creation fallbacks for macOS
  `IOHIDUserDevice` publication failures.
- Removed stale GUI diagnostic state, localization keys, and support-report
  fields that no longer had a user-facing producer.
- Applied discovered nonzero USB alternate settings after claiming the selected
  interface, while preserving explicit record overrides and protocol fallbacks.

## 0.5.0-alpha.4

### Fixed

- (Hopefully) fixed wired Xbox 360 controller startup so OpenJoystickDriver sends the source-backed player-1 solid ring-of-light command instead of leaving the controller flashing after attach.

## 0.5.0-alpha.3

### Added

- Added Sparkle 2 update support, signed appcast generation, and release-feed wiring for notarized DMG updates.
- Added a local release-parity install command for testing the packaged app shape before shipping.

### Changed

- Kept release builds as a universal macOS app while moving release packaging to native Finder DMG styling.
- Switched the daemon LaunchAgent registration to SMAppService on modern macOS so the bundled helper stays associated with the main app.
- Split oversized source and helper-script files into focused modules while preserving existing behavior.

### Fixed

- Fixed packaged app launch failures by adding the runtime framework search path needed for embedded Sparkle.
- Fixed release notarization for embedded Sparkle framework helpers and XPC services.
- Fixed daemon Input Monitoring requests so the native prompt is made by the bundled daemon helper app and appears under the daemon identity.
- Fixed daemon quit/reopen behavior by retaining shutdown signal sources so launchd can terminate and reopen the helper cleanly.
- Fixed the menu-bar setup flow so helper Input Monitoring recovery does not require end-user diagnostics when the helper is disconnected or restarting.
- Fixed update-check error reporting so feed, network, signing, download, and install failures explain the failing stage.

## 0.5.0-alpha.2

### Changed

- Reworked Steam Controller and Xbox Adaptive Joystick request docs into
  tester-first macOS/OJD capture runbooks.
- Improved Steam Controller tester diagnostics after issue #8 showed lizard-mode
  keyboard input but no exact IOHID match for wired `0x28de:0x1102`.

## 0.5.0-alpha.1

### Added

- Added source-backed experimental Steam Controller USB and wireless receiver
  profiles for Valve `10462:4354` and `10462:4418`, including Linux
  `hid-steam.c` input parsing, lizard-mode feature reports, and wireless
  receiver connect/disconnect status gating. Steam Client coexistence and
  physical adapter timing still need hardware testing.
- Added source-backed experimental DualSense profiles for Sony `1356:3302`
  and `1356:3570` using Linux `hid-playstation.c` USB input offsets and
  Bluetooth report `0x31` CRC/input framing. Haptics and physical hardware
  behavior still need testing.
- Added source-backed experimental DualShock 3 profile `1356:616` using
  Linux `hid-sony.c` and SIXAXIS descriptor evidence, including USB feature
  reads, Bluetooth operational-mode feature report `0xf4`, and the Linux
  bogus Bluetooth status-report filter. Rumble, sensors, pairing, and
  physical hardware behavior still need testing.
- Added source-backed experimental Nintendo Switch Pro profile `1406:8201`
  using Linux `hid-nintendo.c` USB startup reports and full-report input
  parsing. USB startup reports are transport-gated away from Bluetooth;
  calibration, rumble, IMU, and physical hardware behavior still need testing.
- Added an Xbox Adaptive Joystick packet-capture checklist for collecting exact
  standalone VID/PID, interface, endpoint, and annotated input packet evidence
  before adding a profile or parser.

### Changed

- Documented experimental controller support with explicit source provenance and
  hardware-validation caveats in the compatibility matrix and LLM context.

## 0.4.1

### Changed

- Reduced background daemon polling while the menu-bar popover is closed.
- Simplified README and signing documentation.

### Fixed

- Reduced launchd health sampling overhead and avoided retaining large `launchctl print` output.

## 0.4.0

### Added

- Added regression coverage for stale active input across parser release events,
  compatibility route handoff, virtual HID neutral reports, and pipeline stop.

### Changed

- Refined the menu-bar and Input Test UI for clearer permissions, game profile,
  live input, packet log, and rumble workflows.
- Added right-click menu-bar fallback behavior so right-click opens the popover.

### Fixed

- Neutralized forwarded virtual output when a controller pipeline stops or a USB
  input loop exits, preventing stale held buttons after disconnect or teardown.
- Fixed Xbox 360 HID compatibility reports so SDL HIDAPI receives the expected
  state packet header, preventing intermittent LB/RB latch/stuck-active states.

## 0.3.1

### Fixed

- Fixed Xbox 360 HID compatibility reports so SDL HIDAPI receives the expected
  state packet header, preventing intermittent LB/RB latch/stuck-active states.

## 0.3.0

### Added

- Added focused Compatibility routing with dedicated per-consumer user-space
  routes for simultaneous SDL apps.
- Added per-controller idle sleep gating that neutralizes forwarded state and
  stops keep-alive traffic while a controller is idle.
- Added focused foreground-routing and sleep-gate regression coverage while
  migrating the test suite to Swift Testing.

### Fixed

- Fixed focused-app handoff so simultaneous SDL consumers no longer hijack each
  other's active controller route.
- Fixed a foreground-consumer misclassification that could freeze controller
  input for a few seconds mid-game.

## 0.2.0

### Added

- Added stock SDL HIDAPI-compatible Xbox 360 rumble path for SDL apps.
- Added release automation for app bundle versions and drag-and-drop DMG packaging.

### Changed

- Switched release packaging from zip-only distribution to a standard macOS DMG.

## 0.1.0-rc.2

### Added

- Added hardware-confirmed DualShock 4 Bluetooth input support through Sony HID
  report `0x11`.
- Added DualShock 4 Bluetooth physical rumble support through output report
  `0x11` with CRC framing.
- Added IOHID transport/report ID propagation so Bluetooth DS4 devices select
  the Sony Bluetooth report path.
- Added regression coverage for observed macOS Bluetooth DS4 report bytes.

### Changed

- Updated compatibility docs and LLM context to distinguish DualShock 4
  Bluetooth support from unsupported non-DS4 Bluetooth controllers.

## 0.1.0-rc.1

### Added

- Added DualShock 4 USB input support with raw HID-normalized stick values.
- Added DualShock 4 physical rumble over HID output report `0x05`.
- Added app-rumble forwarding for Compatibility devices through supported Xbox
  One, Xbox 360, and compact OJD rumble reports.
- Added Input Test controls for live input, packet logs, physical rumble, and
  controller-specific button glyphs.
- Added user-space compatibility identities for SDL 2/3, Apple GameController,
  Generic HID, Xbox 360 HID, and Xbox One HID.

### Changed

- Reworked the menu-bar app so OpenJoystickDriver stays menu-bar-only and keeps
  the status item alive reliably.
- Improved the Input Test window sizing, layout, button grid, and rumble control
  labels.
- Updated README into a shorter user-first guide.
- Moved detailed compatibility information into an emoji-based feature matrix in
  `docs/user/compatibility.md`.
- Clarified Sony controller names: DualShock 4 is supported over USB; DualShock
  3 and DualSense are not implemented.

### Fixed

- Fixed D-pad state tracking so held D-pad directions appear in Input Test state.
- Fixed a daemon/user-space output dispatcher race when creating virtual devices.
- Fixed app rumble parsing so unmarked DriverKit relay bytes are not treated as
  rumble commands.
- Fixed the app delegate lifetime so the menu-bar app can launch and remain
  visible.
