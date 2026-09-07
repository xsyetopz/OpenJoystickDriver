# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Physical HID discovery no longer opens Apple GameController synthetic nodes
  (`AppleGCSyntheticDevice` / `GamePad-1`). Matching now includes Apple's
  documented `GCSyntheticDevice = false` exclusion so `IOHIDDeviceCreate` and
  CoreHID `HIDDeviceClient` never `IOServiceOpen` that shim. The previous skip
  looked up the C macro name instead of the IORegistry key and ran after the
  open. Stock SDL `hid_init` match-all still hangs on a leftover wedged
  GamePad-1 until reboot; OJD does not create that shim (gamecontrollerd does
  when GameController binds an Xbox identity) and cannot drain stuck user
  clients.

### Changed

- Name physical wire families XID, XUSB, GIP, and HID. Catalog driver
  `Xbox360` is now `XUSB`. Automatic compatibility uses one spoof route per
  family: XUSB publishes `045E:028E`, GIP publishes `045E:0B13`, matching HID
  dialects publish DualShock 4 / DualSense / Switch Pro, and remaining HID and
  XID stay Generic HID.
- Menu extra, controller list, and Input Test glyphs follow the published
  virtual identity (official USB product name and system symbol), not the
  physical pad family. Controller list subtitle, detail, and Input Test
  header/title show that published USB product name and VID/PID. GameSir
  G7 SE USB GIP publishing `045E:0B13` is hardware-verified for Apple
  GameController. The Series Bluetooth packer
  emits unsigned stick rest `0x8000` so HIDAPI xboxone BLE idle is signed 0
  (`raw - 0x8000`) without jitter hiding a −1 from `0x7FFF`. Explicit picker
  DualShock 4 (`054C:09CC`), DualSense (`054C:0CE6`), Switch Pro
  (`057E:2009` "Pro Controller"), and Xbox 360 Wired (`045E:028E`) published
  those USB identities from the same GIP pad: `GCController.supportsHIDDevice`
  yes (Switch Pro no longer hangs), and a custom SDL 3.4.16 HIDAPI+IOKit build
  (no GameController.framework) opened them as ps4, ps5, switchpro, and
  xbox360. Switch Pro USB handshake replies are published on the IOKit
  interrupt path so HIDAPI can finish `0x80`/`0x81` setup; Xbox 360 Wired
  uses `bcdDevice` `0x0114` so SDL does not ignore `045E:028E` as a Steam
  virtual pad. GameSir G7 SE GIP init completes: Hello `0x02` then one rest
  `0x20` (36-byte Share report). Later `0x20` is change-only, so a status-only
  packet log is ring-buffer eviction, not missing handshake. No physical
  button bit was captured this session. Steam `hid_init` still hangs.
  Automatic GIP routing stays Series.

### Added

- Selectable DualShock 4 (`dualshock4`, `054C:09CC`), DualSense
  (`dualsense`, `054C:0CE6`), and Switch Pro (`switchpro`, `057E:2009`)
  USB HID packers. Automatic routing publishes the matching first-party
  identity when the physical pad is that dialect. Other HID stays Generic HID.
- Userspace XID parser for original Xbox pads from Linux `xpad`
  `XTYPE_XBOX`. Virtual output stays Generic HID; XID is not a HID identity.
- DualShock 4, DualSense, and Switch Pro virtual HID descriptors now follow
  captured USB layouts (sticks/hat/buttons, not an opaque 63-byte input).
  Switch Pro reports are padded to the 64-byte descriptor length.
- Explicit picker/CLI may publish first-party packer identities on a GIP pad
  for live consumer-bind. Automatic routing stays family-strict (GIP → Series).
- macOS 15+ virtual-device diagnostics fill `GCController.supportsHIDDevice`
  by matching CoreHID snapshots to IOHID devices.
- Report when CoreHID virtual HID creation fails because the Apple Development
  provisioning profile does not include this Mac.

### Fixed

- Development rebuilds keep Input Monitoring: the host is signed with a stable
  team and bundle-id designated requirement instead of a unique-certificate pin.
- After a TCC permission Quit & Reopen, a detached waiter waits until this
  process is gone, boots out leftover Launch Services jobs whose pid is
  dead, then opens the `.app` bundle via Launch Services. Menu Quit and
  SIGTERM still exit without relaunch; they only retire a stale job so
  Spotlight can open again. Do not spawn during terminate. Do not exec the
  Mach-O.

## [0.5.0-beta.4] - 2026-09-05

### Added

- Decode Flydigi Vader 4 Pro over Bluetooth Low Energy (`D7D7:0041`). Face
  buttons, D-pad, sticks, analog triggers, bumpers, Select, Start, stick
  clicks, and Home map from the captured 15-byte report. C, Z, and M1–M4 stay
  diagnostic-only. The 2.4 GHz dongle and wired identities are out of scope.
- Map the WR-007 USB HID receiver (`11C1:5600`) through Generic HID: sparse
  Xbox-style buttons, Z/Rz as the right stick, and Simulation Accelerator/Brake
  as analog triggers. Apple GameController identity is available so
  `GameController.framework` consumers can see the virtual device. Physical
  rumble is not claimed.

### Changed

- Consult device-level compatibility availability when exposing a virtual
  identity, instead of the physical-family overload alone.
- Automatic compatibility uses a protocol × backend catalog: if the physical
  VID/PID is already a first-party device that backend knows, keep that
  identity; otherwise spoof the closest official device for that protocol.
  Xbox 360-family pads publish Microsoft `045E:028E`. GIP pads publish Xbox
  Series `045E:0B13`. DualShock 3/4/5, Switch, Steam Controller, and Flydigi
  wait for virtual report formats. DualShock 1/2 is not a USB HIDAPI protocol.

### Fixed

- Honor macOS Quit & Reopen from a permission grant. The menu-bar app no
  longer relaunches itself during terminate, which left the extra running
  and raced Launch Services (`open` error -600 / “not open anymore”).
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
[0.5.0-beta.4]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.3...0.5.0-beta.4
[0.5.0-beta.3]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.2...0.5.0-beta.3
[0.5.0-beta.2]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.1...0.5.0-beta.2
[0.5.0-beta.1]: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1
