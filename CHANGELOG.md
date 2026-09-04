# Changelog

## 0.5.0-beta.3

_2026-09-04_

- Extra buttons are mapped from packets, not from a catalog of named roles.
  GameSir-style 32-byte GIP reports emit Share from payload byte 15 (under
  Guide). DualSense Mute stays packet-mapped. Unclassified extras stay omitted.
  Renamed catalog/RPC `flags` / `mappingFlags` to `quirks` (encoding and
  subsystem deviations only: `shareOffset`, d-pad/trigger/stick packing, and
  parser-scoped capability markers). Diagnostic mode remains a catalog-backed
  host recipe; none are live until the exact packet is an operational fact.
- Collapsed remapping profile/library contracts to a single live schema version
  (equality with `currentSchemaVersion` only; no supported-version sets).
- Removed the obsolete `xone-hid` / Xbox One HID compatibility identity and its
  probe route. Unknown persisted identity values sanitize to `automatic` on
  load. Use `generic-hid`, `sdl2-3`, `apple-gamecontroller`, or `xbox360-hid`.
- Removed leftover product compatibility shims: named retired-identity registry,
  no-Share Xbox One Bluetooth descriptor fixture, Xbox360 deprecated-name
  source-compatibility tests, and gateway protocol permission fallback defaults.
- Routed human-facing GUI and CLI product copy through the shared localization
  catalog (`OJDLocalized` / `CLILocalized`), expanded the packaged key set, and
  kept non-English locales on explicit English fallbacks except reviewed
  `et-EE` translations of the prior key set.
- Softened product-facing wording toward plain English (no agent-style
  self-narration in menus, settings, and CLI help/errors).
- Removed remaining staging/compat shims: script `rebuild`/`rebuild-fast`/
  top-level `bump-version`/`notarize`/`package release` aliases, stale
  UserDefaults key discards, remapping schema v1 acceptance, soft
  `discoverySource` decode default, and AppKit `NS*Template` icon fallback maps.
- Corrected compatibility guidance to model consumer family and evidence
  separately: ASTRO C40 `9886:0024` remains SDL/PCSX2/Steam-specific, Xbox One
  Bluetooth `045E:02FD` is not an SDL recommendation after reported BT1/BT2
  no-input results, and C40 PS4 `9886:0025` is research-only.
- Automatic compatibility now persists an `automatic` intent and resolves only
  catalog-backed physical modes with adjacent evidence; unrelated families and
  unproven identities fall back to Generic HID.
- Standardized every machine-readable contract on the repository's single live
  JSON Schema Draft 2020-12 definition, with CloudEvents 1.0 as the support
  report envelope. Controller records now contain operational driver facts only;
  source lineage remains in the source lock, testing documents, issues, and Git
  history instead of copied provenance or verification metadata.
- Removed obsolete machine-authored evidence levels, verification claims,
  output-validation plans, compatibility migrations, and schema-shaped JSON
  documentation. Schema changes now update every producer, consumer, override,
  and generated controller record atomically without versioned schemas,
  upcasters, aliases, or fallback decoders.

- Fixed release packaging so the DriverKit extension no longer receives the
  invalid `500001`/`500002` build versions shipped by beta.1 and beta.2;
  semantic prereleases now map to kext-legal versions with strict validation.
- Added plug-and-play signed-DMG setup and bounded recovery/status guidance;
  only macOS-owned approvals remain manual, with no privileged helper or
  allow-any DriverKit access.
- Added fail-closed inspection of historical `systemextensionsctl` versions,
  one-shot stale-DEXT replacement, and cancellation-safe bounded activation
  recovery; valid developer overrides remain available while release conflicts
  are rejected.
- Retained and exposed the fixed canonical GIP/DriverKit ownership for the
  original wired Xbox One controller `045E:02D1`, while preserving direct-USB
  exclusion for entitlement-owned Microsoft devices.
- Kept Xbox 360 startup LED `.notFound` handling best-effort and covered it by
  behavior tests.
- Release/tester provenance now records app and DEXT build-version domains
  separately; the release scripts were migrated to concise stdlib-only Python
  with obsolete shell wrappers removed.
- Retained the source-backed `045E:02FD` tuple for explicit Xbox/Apple research
  routes, while recording the reported BT1/BT2 SDL HIDAPI no-input result as a
  consumer-specific failure. Automatic SDL routing therefore returns Generic
  HID; live Apple GameController checks remain separate.
- Preserved the hardware-verified ASTRO C40 Xbox-mode `9886:0024` SDL default,
  as an explicit SDL/PCSX2/Steam-like route only; automatic routing does not
  substitute it for GIP, XInput, XUSB, Nintendo, or PlayStation families.
  Filtered Apple GameController synthetic HID devices from physical discovery,
  and documented `9886:0025` PS4 mode as research-only pending complete
  descriptor, calibration, input, and output evidence.

All notable changes to OpenJoystickDriver are documented in this file.

## 0.5.0-beta.2

Released: 2026-08-27

### Added

- Added complete GUI profile management for creating, editing, importing,
  deleting, activating, and deactivating profiles, including device and
  application scope, binding capture, turbo/long-hold/double-tap behaviors,
  chords, sequences, layers, and axis tuning.

### Fixed

- Tolerated optional Xbox 360 player-1 ring LED startup output rejections when
  the transport reports an input/output or unsupported result, while keeping
  required output and unrelated packets or parsers on the failure path. The
  CLI record probe and application USB pipeline now share this policy.

## 0.5.0-beta.1

### Added

- Added a compact native menu-bar and settings experience with Overview,
  Controllers, Profiles, Console, and Settings panes, a standard About panel,
  launch-at-login support, and direct GitHub access.
- Added an 80-column wrapped application-service console with stream filtering,
  refresh, and copy controls.
- Added native controller and active-profile notifications with independent
  event and sound preferences, a test action, foreground banner presentation,
  and truthful macOS banner and sound status in Overview and Settings.
- Added availability-selected HID wrappers: macOS 10.15–14 use IOHID for
  physical access and `IOHIDUserDevice` for consumer virtual devices, while
  macOS 15 and later use CoreHID for both roles.
- Added a controller-neutral `OpenJoystickDriverUSB` facade with direct
  app-side IOUSBHost access for available raw/vendor interfaces and a separate
  USBDriverKit route for interfaces owned by OJD's restricted system extension.
- Added evidence-based USB route selection, stable route-qualified service
  identities, pre-open configuration and alternate-setting options, and focused
  no-fallback/ownership contract tests.
- Added documentation for Apple's installed controller personalities, USB
  ownership boundaries, CoreHID virtual-device entitlement ownership, and the
  separate development and Developer ID signing requirements.

### Fixed

- Prevented live polling from cancelling full profile and controller-identity
  refreshes, removed persistent loading states, and made controller connection,
  disconnection, and active-profile changes update without replacing visible UI
  state with loading placeholders.
- Corrected console stream classification so ordinary application-service
  startup output is not presented as an error.
- Kept Compatibility virtual gamepads stable across foreground-application
  changes and made `sdl2-3` publish the hardware-verified ASTRO `9886:0024`
  identity with its exact Xbox 360 HIDAPI descriptor and reports. PCSX2 Nightly
  accepted input and sent working rumble through this SDL route.
- Prevented superseded delayed rumble stops from silencing newer accepted
  output commands when applications rapidly replace motor strengths. This is
  scheduling hardening; it does not add an SDL output protocol to identities
  for which an application emits no rumble report.
- Fixed an IOUSBHost crash caused by attempting to resize kernel-backed transfer
  buffers; interrupt transfers now use bounded memory copies and the required
  zero completion timeout.
- Deduplicated wired controller discovery across HID and raw-USB paths when both
  paths report the same physical device, and expanded controller details to
  avoid cramped long-value columns.
- Corrected DriverKit signing diagnostics to require the USB transport
  entitlement and reject HIDDriverKit, virtual-device, and allow-any
  entitlements in the USB DEXT.
- Restricted development and production USBDriverKit configuration to Apple's approved
  Microsoft GIP family: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`,
  `045E:0B00`, `045E:0B0A`, and `045E:0B12`.
- Made direct IOUSBHost discovery start from catalog-supported device services,
  so controllers such as the GameSir G7 SE can select configuration 1 before
  their GIP interface exists.
- Made install and DEXT diagnostics accept an activated, idle extension when no
  entitled Microsoft device is connected and compare the actual packaged short
  and build versions instead of assuming `1.0`.
- Resolved all SwiftLint findings in repository-owned Swift sources, tests, and
  `Package.swift`; `just lint` now checks only those paths.

### Changed

- Made Apple GameController the recommended default compatibility identity,
  presented identity choices in a compact grid, removed duplicate empty states
  and redundant advanced shortcuts, and reduced unused space throughout the
  settings window.
- Reworked the menu-bar menu around Show, Refresh, Settings, connected
  controllers, Help, About, and Quit, with native controller protocol icons and
  the application icon as the preferred status-item image.
- Folded the hardware-verified ASTRO Xbox 360 HIDAPI implementation into the
  SDL-specific `sdl2-3` profile and removed the now-redundant `x360-hid`
  selection and diagnostic spoof RPC/CLI surface. Hardware testing rejected
  the former GameStop `1BAD:F901` SDL identity because rumble was absent or a
  rare faint pulse, and rejected Microsoft Bluetooth `045E:02E0` and
  `045E:02FD` spoof variants because neither delivered input. `xone-hid`
  remains a legacy Xbox One Bluetooth-shaped generic-HID identity after its GameSir G7 SE
  input and rumble failure.
- Defined compatibility profiles by the consumer API they target: `sdl2-3`
  for SDL 2/3 applications, `apple-gamecontroller` for `GCController`
  applications, `generic-hid` as the unsupported/unknown-consumer fallback,
  and `xone-hid` for experimental generic-HID compatibility. Neither profile
  is XInputHID, XUSB, or GIP emulation; `xone-hid` is retained only for legacy
  persisted configurations.
- Consolidated the supported headless CLI around the current `map`, `compat`,
  `extension`, `permissions`, and `diagnose` command surfaces.
- Removed browser diagnostics and obsolete application-service start/restart
  lifecycle paths; the installed app is now launched directly when needed.
- Removed active backwards-compatibility aliases, legacy DriverKit signing
  fallbacks, legacy virtual-device serial decoding, and permissive self-test
  payload decoding.
- Removed foreground-consumer HID routing, per-application virtual-device
  replacement, and the obsolete bundled SDL mapping file.
- Removed SwiftUSB and libusb. Raw/custom USB now uses Apple's IOUSBHost family
  directly or through the restricted USBDriverKit extension on macOS 10.15 and
  later.
- Preserved the Apple-approved external identity
  `com.openjoystickdriver.XboxUSBDevice` while renaming internal transport and
  configuration abstractions so controller brands do not determine routing.
- Reserved the USB DEXT for an observed DEXT-owned service or an exact
  Apple-entitled model. Direct-open failures never silently retry through
  another backend.
- Kept `com.apple.developer.hid.virtual.device` on the standard application
  process only. The USB DEXT contains only its DriverKit base and exact USB
  transport entitlements and never publishes virtual HID devices.
- Split local Apple Development and CI Developer ID signing assets. Release CI
  now imports only the Developer ID Application identity and separate host and
  `XboxUSBDevice` Developer ID profiles, and no longer installs libusb.
- Matched the USB entitlement to Apple's issued seven-dictionary
  provisioning payload rather than an `idProductArray` shorthand.
- Made the app's source `Info.plist` the canonical package version declaration;
  app, DEXT, package, and local-install defaults now inherit it.
- Removed the daemon and relay architecture, including
  `com.openjoystickdriver.daemon`; the persistent application owns controller
  semantics, virtual output, and its authenticated local command service.

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
- Replaced the manually maintained DriverKit extension with a deterministic
  SwifterKit-generated relay and made the Swift relay configuration the sole
  application-owned DriverKit source.
- Made the Compatibility virtual device the sole consumer-gamepad output
  backend and limited the vendor-defined DriverKit relay to integrity
  diagnostics, removing output modes that could route gameplay reports only to
  a non-gamepad relay.
- Removed obsolete interactive capture, menu-app runtime soak, and private Apple
  catalog audit controls.
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
- Updated the runtime to SwiftUSB 0.1.2 and removed OpenJoystickDriver-specific
  libusb descriptor shims and extra USB contexts.
- Lowered the Swift test deployment target from macOS 26 to the maintained
  macOS 14 compatibility floor.

### Fixed

- Cleared the internal option flag from GIP rumble frames, which Xbox One
  controllers silently discard; physical rumble on all four motors verified on
  045E:02D1 hardware.
- Made manual update checks select the greatest valid GitHub tag for the chosen
  stable or prerelease channel and report that remote tag when the installed
  build is already newer.
- Corrected permission status to use authoritative access checks from the main
  application and removed the obsolete helper-selection workflow.
- Made virtual-device self-test probe Compatibility with neutral reports and
  derive DriverKit relay strictness from the signed host entitlement. Entitled
  hosts still require relay delivery; hosts awaiting the entitlement report the
  relay diagnostic as optional and inconclusive.
- Added bounded compatibility-device creation fallbacks for macOS
  `IOHIDUserDevice` publication failures.
- Removed stale GUI diagnostic state, localization keys, and support-report
  fields that no longer had a user-facing producer.
- Applied discovered nonzero USB alternate settings after claiming the selected
  interface, while preserving explicit record overrides and protocol fallbacks.
- Left unsupported vendor-specific raw USB devices unclaimed instead of opening
  an unusable generic pipeline that could exclude other controller software.
- Corrected the Xbox One Controller 1537 record to use hardware-reported
  endpoints `0x81`/`0x01` and configuration 1 before interface claim.
- Restored the Logitech F310 XInput record's hardware-reported `0x02` output
  endpoint so Xbox 360 startup output does not abort the input pipeline.
- Narrowed the Razer Wolverine V2 and V3 GIP records to captured transport
  evidence; Share, paddles, configuration, and delay behavior remain unverified.
- Prevented overlapping state-bridge waiter access from triggering Swift's
  dynamic exclusivity trap under concurrent relay tests.
- Made SwiftPM toolchain and deployment-target repair use the package manager's
  canonical clean operation instead of deleting module directories directly.
- Made development signing require only the Apple Development host and
  DriverKit profiles; the publisher-only Developer ID profile is now optional
  unless release configuration is requested.
- Added a development-only signing mode for the currently approved legacy
  DriverKit user-client profile. It omits the malformed user-client entitlement
  from the signed host so the app and Compatibility output can run while relay
  diagnostics remain unavailable; release and CI require the exact allowlist.
- Updated the reviewed SwifterKit branch revision so HID-only generated
  extensions no longer link unavailable, unused DriverKit family frameworks.
- Documented where each signing identity, App ID capability, provisioning
  profile, notarization credential, and generated environment value comes from.

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
