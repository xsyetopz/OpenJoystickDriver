# Contributor Documentation

These pages are for contributors and maintainers. To use the app, read the [user guides](../wiki/Home.md).

## Contents

- [Development](#development)
- [SDK](#sdk)
- [Localization](#localization)
- [Hardware Evidence](#hardware-evidence)

## Development

For contributors who build, sign, or change the app. Start with [Architecture](development/architecture.md).

- [Apple Controller Ownership and Transport Evidence](development/apple-controller-ownership.md)
- [Architecture](development/architecture.md)
- [Building From Source](development/building-from-source.md)
- [CLI and Application Runtime](development/cli-and-runtime.md)
- [Compatibility Source Notes](development/compatibility-sources.md)
- [Document-Defined Protocol Families](development/document-defined-families.md)
- [Environment Files](development/environment.md)
- [Experimental Controller Status](development/experimental-controllers.md)
- [Implementation Status](development/implementation-status.md)
- [InputConfig Preset Library: Import Measurement](development/inputconfig-presets.md)
- [Installer Format: DMG or Package](development/installer-format.md)
- [Interface Audit: 0.6.0-alpha.2](development/interface-audit.md)
- [Public Endpoint Design](development/public-endpoint-design.md)
- [Menu-Bar and Settings UI Architecture](development/menu-bar-settings-architecture.md)
- [Reconcile a GitHub Release](development/releases.md)
- [Remapping](development/remapping.md)
- [Advanced Remapping Controls](development/remapping-advanced-controls.md)
- [Remapping Calibration](development/remapping-calibration.md)
- [Remapping Input Samples](development/remapping-input-samples.md)
- [Remapping Motion Processing](development/remapping-motion.md)
- [Scripting Surfaces](development/scripting-surfaces.md)
- [Signing the App and XboxUSBDevice DEXT](development/signing.md)
- [Source Topology](development/source-topology.md)
- [Terminology Survey](development/terminology-survey.md)
- [Create a Local Tester Build](development/tester-builds.md)
- [USB DriverKit Entitlement Candidates](development/usb-entitlement-candidates.md)
- [Virtual Profile Selection: What GameController and SDL3 Read](development/virtual-profile-selection.md)
- [Wire Protocols](development/wire-protocols.md)
- [Xbox Fallback Identities](development/xbox-identities.md)
- [Import Controller Identities From Linux xpad](development/xpad-import.md)

## SDK

For developers who write a client for the local endpoint.

- [SDK Endpoint](sdk/endpoint.md): Handshake, messages, errors, and grants.
- [WebRTC Bridge](sdk/webrtc-bridge.md): Carries a controller between two Macs.

## Localization

For translators and reviewers.

- [Localization Review 0.6.0](localization/review-0.6.0.md): The 20 non-English locales.

## Hardware Evidence

For testers who check a controller and for maintainers who judge compatibility claims. Read [Consumer-Binding Evidence](testing/consumer-binding.md) first, then [Test a Controller Record](testing/controller-record.md).

- [8BitDo Tester Checks](testing/8bitdo-tester-checks.md)
- [8BitDo Ultimate 2](testing/8bitdo-ultimate-2.md)
- [8BitDo Ultimate 2C Wireless](testing/8bitdo-ultimate-2c.md)
- [Browser Gamepad API Manual Evidence](testing/browser-gamepad-api.md)
- [Consumer-Binding Evidence](testing/consumer-binding.md)
- [Test a Controller Record](testing/controller-record.md)
- [Flydigi Tester Checks](testing/flydigi-tester-checks.md)
- [Flydigi Apex 4 (DInput)](testing/flydigi-apex-4.md)
- [Flydigi Vader 4 Pro (Bluetooth)](testing/flydigi-vader-4-pro.md)
- [Flydigi Vader 5 Pro 2.4 GHz Dongle](testing/flydigi-vader-5-pro.md)
- [Flydigi Vader 5S (USB)](testing/flydigi-vader-5s.md)
- [Test the GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC](testing/gamesir-family.md)
- [Gyro-to-Stick Hardware Check](testing/gyro-stick.md)
- [Probe macOS Haptics Backends](testing/haptics-backends.md)
- [Joy-Con Input Validation](testing/joy-con.md)
- [Test Logitech F310 XInput Mapping](testing/logitech-f310.md)
- [Test the Nacon Revolution X Pro](testing/nacon-revolution-x.md)
- [NITHO MLT-KRMA-K Test Record](testing/nitho-mlt-krma-k.md)
- [Test Physical Output](testing/physical-output.md)
- [Test Razer Wolverine V3 Tournament Edition](testing/razer/v3-te.md)
- [Testing the Razer Wolverine V2](testing/razer/wolverine-v2.md)
- [Test the SCUF Envision Pro](testing/scuf-envision-pro.md)
- [SIXAXIS and DUALSHOCK 3](testing/sixaxis-vs-ds3.md)
- [Third-Party PS3 Controllers](testing/ps3-third-party.md)
- [Third-Party DualSense Controllers](testing/dualsense-third-party.md)
- [Wired Switch Input-Only Pads](testing/switch-input-only.md)
- [Test Switch 2 Controllers](testing/switch-2.md)
- [Steam Controller (2026, Triton)](testing/steam-triton.md)
- [Test Steam Controller Hardware](testing/steam-controller.md)
- [Test the Steam Deck Controller](testing/steam-deck.md)
- [Test a Tester Build](testing/tester-builds.md)
- [Test WR-007 USB HID Receiver](testing/wr-007.md)
- [Test an Xbox 360 Wireless Receiver](testing/xbox-360-wireless-receiver.md)
- [Capture Xbox Adaptive Joystick Packets](testing/xbox-adaptive-joystick.md)
- [Xbox Nano Controller Test Record](testing/xbox-nano.md)
- [Xbox One Controller Model 1537 (`045E:02D1`) Detection](testing/xbox-one-02d1.md)
- [Test Microsoft Xbox One Controller (Model 1537)](testing/xbox/1537.md)
- [ZD O+ in Switch Mode](testing/zd-o-plus.md)
