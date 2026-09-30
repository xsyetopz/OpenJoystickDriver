# Contributor documentation

This directory holds the development notes and hardware-evidence records for OpenJoystickDriver contributors and maintainers; user guides live in [`docs/`](../docs/README.md).

## Development

- [Apple Controller Ownership And Transport Evidence](development/apple-controller-ownership.md): How macOS ownership determines which Apple USB transport can reach a physical interface.
- [Architecture](development/architecture.md): The application bundle, persistent host process, and generated USBDriverKit system extension.
- [Building From Source](development/building-from-source.md): Building, checking, and installing through `./Scripts/ojd`.
- [CLI And Application Runtime](development/cli-and-runtime.md): The menu-bar app runtime and the headless expert CLI.
- [Compatibility Source Notes](development/compatibility-sources.md): External projects that provide design or protocol evidence.
- [Environment Files](development/environment.md): The optional local environment file that repository scripts load.
- [Experimental Controller Status](development/experimental-controllers.md): Entries with implementation work but incomplete hardware evidence.
- [Implementation Status](development/implementation-status.md): The persistent application runtime and what it owns.
- [Controller Issue Audit](development/issue-audit.md): Implemented behavior versus observations on reported hardware.
- [Menu-Bar And Settings UI Architecture](development/menu-bar-settings-architecture.md): The architecture decision for the menu-bar and settings UI.
- [Reconcile A GitHub Release](development/releases.md): The procedure after the release commit and changelog are complete.
- [Remapping](development/remapping.md): Profile actions and chord timing, with links to the focused remapping pages.
- [Advanced Remapping Controls](development/remapping-advanced-controls.md): Angular, area, ring, scroll, steering, lean, and trigger modes.
- [Remapping Calibration](development/remapping-calibration.md): Physical motion conversion, factory calibration, and fusion.
- [Remapping Input Samples](development/remapping-input-samples.md): Motion, touch, extra-control, and paired-controller input.
- [Remapping Motion Processing](development/remapping-motion.md): Per-device motion processing, projections, tuning, and layer overrides.
- [Signing The App And XboxUSBDevice DEXT](development/signing.md): The two independently provisioned code items and their signing steps.
- [Source Topology](development/source-topology.md): SwiftPM targets, capability directories, and durable source owners.
- [Create A Local Tester Build](development/tester-builds.md): Maintainer steps for making a tester build.
- [USB DriverKit Entitlement Candidates](development/usb-entitlement-candidates.md): Catalog identities that are candidates for a USB DriverKit entitlement application.
- [Wire Protocols](development/wire-protocols.md): How OJD classifies physical pads by host wire protocol.
- [Xbox Fallback Identities](development/xbox-identities.md): What a safe published virtual profile needs beyond a product name.
- [Import Controller Identities From Linux xpad](development/xpad-import.md): How the generated runtime catalog takes identities from pinned sources.

## Hardware evidence

- [8BitDo Ultimate 2C Wireless](testing/8bitdo-ultimate-2c.md): Testing each mode, which enumerates as a different identity.
- [Browser Gamepad API Manual Evidence](testing/browser-gamepad-api.md): The manual protocol for browser Gamepad API evidence.
- [Catalina Foreground Test Kit](testing/catalina-testkit.md): Running the foreground app and headless CLI on macOS 10.15.
- [Consumer-Binding Evidence](testing/consumer-binding.md): How to interpret compatibility claims, with observed consumer results.
- [Test A Controller Record](testing/controller-record.md): Validating candidate OJD JSON records without Apple Developer Program membership.
- [Flydigi Vader 4 Pro (Bluetooth)](testing/flydigi-vader-4-pro.md): The Bluetooth identity `D7D7:0041` observed on macOS 26.5.
- [Test The GameSir G7 Pro, Cyclone 2, And G7 Pro 8K PC](testing/gamesir-family.md): Source-backed records that are not hardware-verified.
- [Probe macOS Haptics Backends](testing/haptics-backends.md): Diagnostics that separate backend inventory, GameController haptics, SDL output, and direct rumble.
- [Joy-Con Input Validation](testing/joy-con.md): The left and right Joy-Con records imported from pinned Nintendo sources.
- [Test Logitech F310 XInput Mapping](testing/logitech-f310.md): The F310 test for issue #11.
- [Test The Nacon Revolution X Pro](testing/nacon-revolution-x.md): The test for issue #21.
- [Test Physical Output](testing/physical-output.md): Manual output tests generated from a connected controller's capabilities.
- [Test Razer Wolverine V3 Tournament Edition](testing/razer/v3-te.md): The test for issue #14.
- [Testing The Razer Wolverine V2](testing/razer/wolverine-v2.md): The test procedure for issue #19.
- [Test The SCUF Envision Pro](testing/scuf-envision-pro.md): The wired record for HID identity `2E95:434D`.
- [Shanwan PS3/PC pads](testing/shanwan-ps3-pc.md): The Shanwan chip family that does not speak Sony's protocol.
- [Wired Switch input-only pads](testing/switch-input-only.md): Licensed wired Switch pads that send one fixed HID report.
- [Switch 2 controllers over USB](testing/switch-2.md): The Switch 2 Pro Controller, Joy-Con 2 and NSO GameCube controller over USB.
- [Steam Controller (2026, Triton)](testing/steam-triton.md): The 2026 Steam Controller over USB, Bluetooth LE and its dongles.
- [Test Steam Controller Hardware](testing/steam-controller.md): The original Steam Controller over USB, its wireless receiver, and Bluetooth LE.
- [Test the Steam Deck Controller](testing/steam-deck.md): The Deck's built-in controller when macOS runs on Deck hardware.
- [Test A Tester Build](testing/tester-builds.md): How testers check a fix with a notarized tester DMG.
- [Test WR-007 USB HID Receiver](testing/wr-007.md): The test for issue #31.
- [Test An Xbox 360 Wireless Receiver](testing/xbox-360-wireless-receiver.md): The request for issue #9 about three Microsoft receiver IDs.
- [Capture Xbox Adaptive Joystick Packets](testing/xbox-adaptive-joystick.md): The USB identity and packets needed before adding a device record.
- [Test Microsoft Xbox One Controller (Model 1537)](testing/xbox/1537.md): The procedure for issue #18.
