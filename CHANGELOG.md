# Changelog

All notable project changes are recorded here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Map the wired GameSir K1 (`3537:1082`) through Generic HID: the WR-007 layout
  (sparse Xbox-style buttons, Z/Rz as the right stick, Simulation triggers) with
  Brake as the left trigger and Accelerator as the right, and Guide on button 13.
- Decode Flydigi Vader 4 Pro over Bluetooth Low Energy (`D7D7:0041`). Face
  buttons, D-pad, sticks, analog triggers, bumpers, Select, Start, stick
  clicks, and Home map from the captured 15-byte report. C, Z, and M1–M4 stay
  diagnostic-only. The 2.4 GHz dongle and wired identities are out of scope.
- Map the WR-007 USB HID receiver (`11C1:5600`) through Generic HID: sparse
  Xbox-style buttons, Z/Rz as the right stick, and Simulation Accelerator/Brake
  as analog triggers. Apple GameController identity is available so
  `GameController.framework` consumers can see the virtual device. Physical
  rumble is not claimed.
- Run Ruff, Pyright, ShellCheck, swift-format, SwiftLint, Python unittest, and SwiftPM directly from Just and CI. Keep `./Scripts/ojd` for repository-specific operations.
- Add source-backed XID input and independent 16-bit motor output for cataloged original-Xbox controllers. Physical rumble remains unverified; virtual output remains Generic HID because XID is not HID.
- Add GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC input, heartbeats, extra controls, telemetry, and model-specific lighting. G7 Pro `3537:100A` and `3537:1022` stay input-only until a configuration-ready mode is hardware-verified.
- Add wired SCUF Envision Pro `2E95:434D` Generic HID input from report 6. Existing `2E95:0504` GIP behavior is unchanged.
- Add selectable DualShock 4 (`dualshock4`, `054C:09CC`), DualSense (`dualsense`, `054C:0CE6`), and Switch Pro (`switchpro`, `057E:2009`) USB HID packers and captured-layout descriptors. Switch Pro reports are padded to 64 bytes.
- Let the picker and CLI publish those first-party identities from a GIP pad for consumer testing; automatic GIP routing remains Xbox Series.
- On macOS 15+, correlate CoreHID and IOHID snapshots for `GCController.supportsHIDDevice` diagnostics, and report provisioning profiles that exclude the current Mac.

### Changed

- Consult device-level compatibility availability when exposing a virtual
  identity, rather than the physical-family overload alone.
- **BREAKING:** Repository automation now uses `Scripts/` and `Tools/`. `./Scripts/ojd` is the only supported script entry point; lowercase aliases were removed.
- **BREAKING:** OpenJoystickDriver JSON now has one unversioned lowerCamelCase contract. Profiles and remapping libraries reject schema-version tags and legacy snake-case names.
- Name wire families XID, XUSB, GIP, and HID; rename catalog driver `Xbox360` to `XUSB`. Automatic publishing is family-specific: XUSB uses Xbox 360, GIP uses Xbox Series, matching HID dialects use their first-party identity, and other HID or XID devices use Generic HID.
- Show the published identity's official product name, VID/PID, symbol, and glyphs throughout the UI. Consumer-bind results, report details, and evidence limits are recorded in [consumer-binding evidence](docs/testing/consumer-binding.md), [wire protocols](docs/development/wire-protocols.md), and the [GameSir record](docs/testing/gamesir-family.md). Automatic GIP routing remains Xbox Series.

### Removed

- Remove standalone HID set-report, haptics-backend, and DMG-background probes, plus the undispatched build `nuke` route. Supported diagnostics remain under `./Scripts/ojd diagnose`.
- Remove repository-local source-layout, source-size, script-prose, and SwiftLint-wrapper checks, plus generic dispatcher lint, format, aggregate-check, capability-test, and Swift-test routes.

### Fixed

- Exclude Apple GameController synthetic HID nodes before opening them. This avoids creating new wedged `GamePad-1` clients; existing stuck clients still require a reboot. See [Apple controller ownership](docs/development/apple-controller-ownership.md).
- Keep Input Monitoring across development rebuilds by signing the host with a stable team and bundle-ID requirement.
- Complete TCC Quit & Reopen through Launch Services after the old process exits. Normal Quit and SIGTERM do not relaunch the app.
- Write rumble and player-indicator packets for ZD Ultimate Legend
  (`413D:2104`) to interrupt OUT `0x02`. The Xbox 360 default OUT `0x01` is
  absent on this pad, so those writes failed with `notFound`.

## [0.5.0-beta.3] - 2026-09-04

### Added

- Install from a signed DMG with plug-and-play setup. Only macOS-owned
  approvals stay manual.
- Translate GUI and CLI copy for packaged locales. Keyboard destinations use
  SF Symbols when macOS provides them, with localized text as fallback.

### Changed

- Map extra buttons from packets. GameSir-style 32-byte GIP reports emit Share
  from payload byte 14. DualSense Mute stays packet-mapped.
- Hide periodic GIP announce frames from packet-capture console and Copy All.
  Export still includes them.
- Promote empty remapping libraries from the retired schema on load so a blank
  Profiles store no longer fails as unsupported.
- Persist automatic compatibility as `automatic` and resolve only catalog-backed
  physical modes. Unrelated or unproven identities fall back to Generic HID.
- Rename catalog and RPC `flags` to `quirks`.
- Treat ASTRO C40 `9886:0024` as SDL/PCSX2/Steam-specific. Do not recommend Xbox
  One Bluetooth `045E:02FD` for SDL after reported no-input results. Treat C40
  PS4 `9886:0025` as research-only.

### Removed

- Remove the `xone-hid` compatibility identity. Sanitize unknown persisted
  identities to `automatic`.

### Fixed

- Relaunch the menu-bar extra after macOS Quit & Reopen from a permission grant.
- Stop Launch Services from re-opening the menu-bar app during install probes,
  which showed “The application is not open anymore” and left a blank extra.
- Start the signed app after local replace so LaunchServices `open` does not
  fail with -600.
- Give the DriverKit extension a legal build version. Semantic prereleases no
  longer ship as `500001` or `500002`.
- Replace a stale DriverKit extension and recover bounded activation failures.

## [0.5.0-beta.2] - 2026-08-27

### Added

- Manage profiles in the GUI: create, edit, import, delete, and activate, with
  device and application scope, binding capture, turbo, long-hold, double-tap,
  chords, sequences, layers, and axis tuning.

### Fixed

- Tolerate optional Xbox 360 player-1 ring LED startup output rejections.

## [0.5.0-beta.1] - 2026-08-25

### Added

- Add a native menu-bar and settings app with Overview, Controllers, Profiles,
  Console, and Settings, plus About, launch-at-login, and GitHub access.
- Add an application-service console with stream filtering, refresh, and copy.
- Notify on controller and active-profile events, with independent event and
  sound preferences.
- Use IOHID on macOS 10.15–14 and CoreHID on macOS 15+ for physical HID and
  virtual devices.
- Open raw USB with IOUSBHost, or USBDriverKit for interfaces owned by the
  restricted system extension.

### Changed

- BREAKING: Remove the daemon and relay. The app owns controller semantics,
  virtual output, and the local command service.
- BREAKING: Remove SwiftUSB and libusb. Raw USB uses IOUSBHost or USBDriverKit.
- Make Apple GameController the recommended default compatibility identity.
- Target consumer APIs: `sdl2-3` for SDL 2/3, `apple-gamecontroller` for
  `GCController`, and `generic-hid` as fallback. Fold the hardware-verified
  ASTRO Xbox 360 HIDAPI path into `sdl2-3` and drop `x360-hid`.
- Limit USBDriverKit to Apple's approved Microsoft GIP family: `045E:02D1`,
  `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and
  `045E:0B12`.
- Rework the menu-bar menu around Show, Refresh, Settings, connected
  controllers, Help, About, and Quit.

### Removed

- Remove browser diagnostics and obsolete application-service start/restart
  paths.
- Remove foreground-consumer HID routing, per-application virtual-device
  replacement, and the bundled SDL mapping file.

### Fixed

- Keep controller and profile UI updates from replacing visible state with
  loading placeholders.
- Stop classifying ordinary application-service startup as a console error.
- Keep Compatibility virtual gamepads stable across foreground-app changes.
  `sdl2-3` publishes the hardware-verified ASTRO `9886:0024` identity.
- Prevent superseded delayed rumble stops from silencing newer accepted output.
- Fix an IOUSBHost crash from resizing kernel-backed transfer buffers.
- Deduplicate wired discovery when HID and raw USB report the same device.
- Require the USB transport entitlement in DriverKit signing diagnostics.
- Let controllers such as the GameSir G7 SE select configuration 1 before the
  GIP interface exists.
- Accept an activated idle DriverKit extension when no entitled Microsoft
  device is connected.

## [0.5.0-alpha.5] - 2026-07-12

### Added

- Reach the running app from headless commands over a local authenticated RPC.
- Generate the controller catalog from pinned Linux kernel sources.

### Changed

- BREAKING: Move controller processing into the main app. Remove the embedded
  daemon, LaunchAgent, and XPC helper.
- Register the main app as the login item and make it the sole owner of Input
  Monitoring and Accessibility requests.
- Make the Compatibility virtual device the sole consumer-gamepad output.

### Fixed

- Clear the internal option flag from GIP rumble frames so Xbox One controllers
  accept rumble.
- Select the greatest valid GitHub tag for manual update checks.
- Report permission status from the main app instead of a helper-selection
  workflow.
- Leave unsupported vendor-specific USB devices unclaimed.
- Use hardware-reported endpoints for Xbox One Controller 1537 and Logitech
  F310 XInput.

## [0.5.0-alpha.4] - 2026-06-10

### Fixed

- Send the player-1 solid ring-of-light command on wired Xbox 360 attach
  instead of leaving the controller flashing.

## [0.5.0-alpha.3] - 2026-06-08

### Added

- Add Sparkle 2 updates from the notarized DMG feed.
- Add a local install that matches the packaged app.

### Changed

- Keep release builds universal and package them as Finder-styled DMGs.
- Register the daemon LaunchAgent with SMAppService on modern macOS.

### Fixed

- Launch the packaged app by adding the Sparkle runtime search path.
- Notarize embedded Sparkle helpers and XPC services.
- Request daemon Input Monitoring under the daemon identity.
- Let launchd terminate and reopen the daemon helper cleanly.
- Name the failing stage when an update check fails.

## [0.5.0-alpha.2] - 2026-06-06

### Changed

- Improve Steam Controller tester diagnostics after wired `0x28de:0x1102`
  showed lizard-mode keyboard input without an exact IOHID match.

## [0.5.0-alpha.1] - 2026-06-06

### Added

- Add experimental Steam Controller USB and wireless receiver support for
  `10462:4354` and `10462:4418`.
- Add experimental DualSense USB and Bluetooth support for `1356:3302` and
  `1356:3570`.
- Add experimental DualShock 3 support for `1356:616`.
- Add experimental Nintendo Switch Pro USB support for `1406:8201`.

## [0.4.1] - 2026-05-31

### Changed

- Reduce background polling while the menu-bar popover is closed.

### Fixed

- Reduce launchd health-sampling overhead.

## [0.4.0] - 2026-05-24

### Changed

- Clarify menu-bar and Input Test workflows for permissions, profiles, live
  input, packet log, and rumble.
- Open the popover on right-click.

### Fixed

- Neutralize virtual output when a controller disconnects or a USB input loop
  exits, so buttons do not stay held.

## [0.3.1] - 2026-05-24

### Fixed

- Include the expected SDL HIDAPI state packet header in Xbox 360 HID reports
  so LB/RB no longer stick.

## [0.3.0] - 2026-05-24

### Added

- Route Compatibility per SDL consumer so simultaneous SDL apps can share
  controllers.
- Gate idle controllers: neutralize forwarded state and stop keep-alives.

### Fixed

- Stop simultaneous SDL apps from hijacking each other's controller route.
- Fix a foreground-consumer misclassification that could freeze input mid-game.

## [0.2.0] - 2026-05-21

### Added

- Add SDL HIDAPI-compatible Xbox 360 rumble for SDL apps.

### Changed

- Distribute releases as a standard macOS DMG.

## [0.1.0-rc.2] - 2026-05-13

### Added

- Add DualShock 4 Bluetooth input and rumble through Sony HID report `0x11`.

## [0.1.0-rc.1] - 2026-05-13

### Added

- Add DualShock 4 USB input and rumble.
- Forward app rumble to Compatibility devices through supported Xbox One, Xbox
  360, and compact rumble reports.
- Add Input Test controls for live input, packet logs, physical rumble, and
  button glyphs.
- Add user-space compatibility identities for SDL 2/3, Apple GameController,
  Generic HID, Xbox 360 HID, and Xbox One HID.

### Changed

- Keep the app menu-bar-only with a reliable status item.

### Fixed

- Show held D-pad directions in Input Test.
- Fix an output-dispatcher race when creating virtual devices.
- Keep the menu-bar app alive after launch.

[Unreleased]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.4...HEAD
[0.5.0-beta.3]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.2...0.5.0-beta.3
[0.5.0-beta.2]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.1...0.5.0-beta.2
[0.5.0-beta.1]: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1
