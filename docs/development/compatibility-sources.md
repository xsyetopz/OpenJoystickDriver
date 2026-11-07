# Compatibility Source Notes

External projects provide design or protocol evidence, not runtime dependencies or proof of macOS hardware support. Relevant SDL discussions: [#11002](https://github.com/libsdl-org/SDL/issues/11002), [#15663](https://github.com/libsdl-org/SDL/issues/15663), [#15790](https://github.com/libsdl-org/SDL/issues/15790), and [#15183](https://github.com/libsdl-org/SDL/pull/15183).

## Source, License, and Capture Boundaries

The approved compatibility break is an owner decision, not a conclusion that external users are absent. The sources below provide only the stated evidence; they do not authorize additional OJD output profiles or prove a Mac ABI.

- **Official:** Microsoft's [GameInput device-type documentation (GDK 2604)][1] distinguishes generic HID from XUSB, XInputHID, and GIP. The versioned page was last updated 2026-04-22. Apple's [controller backward-compatibility documentation][2] describes a framework compatibility feature. Neither page specifies the exact `045e:0b0c` descriptor/report ABI used by OJD's proposed profile. These are factual documentation references; no source code is copied.
- **Upstream:** SDL's [`controller_list.h` at `fa2c02bb6e21974a89ea9824bc53c9932abe5f9c`][3] lists `045e:0b0c` as the Xbox Adaptive Controller over Bluetooth, and `SDL_IsJoystickBluetoothXboxOne` (`src/joystick/SDL_joystick.c:3166-3181`) names it, so SDL's HIDAPI Xbox One driver takes the virtual device instead of leaving it to GameController (`src/joystick/hidapi/SDL_hidapi_xboxone.c:370-379`); that driver treats it as USB GIP because the macOS transport is `Virtual`, not `Bluetooth`. Apple's `AppleGameControllerPersonality.kext` lists `045e:0b0c` without `GCIOMatchVirtual`, so GameController does not bind the virtual device (`GameControllerPersonalityMatchTests`). SDL's [`LICENSE.txt` at the same commit][4] contains SDL's three-condition permissive license. The identity row supports consumer classification only; it is not descriptor or packet evidence. No SDL code is copied.
- **Upstream:** The repository source lock pins Linux [`drivers/input/joystick/xpad.c` at `44696aa3a489d2baf58efa61b37833f100072bee`][5] (SHA-256 `c24c86cbb74e74eba751e50899f3137ef0439e0d2a2c391a2e7c7d7556e87278`, recorded in [ControllerSources.lock.json](../../ControllerSources.lock.json)). Its file header gives `GPL-2.0-or-later`. This is protocol-family context, not macOS publication evidence. No Linux code is copied. The other mutable consumer and community references were not used to support this publication decision and are not represented here as commit-pinned or license-reviewed evidence. Their protocol claims remain outside this source record; review them before relying on those claims for protocol implementation.
- **Captured:** No committed genuine `045e:0b0c` descriptor/report capture was found. `docs/testing/consumer-binding.md` and `docs/testing/haptics-backends.md` preserve historical/user-reported consumer observations, including failed `02fd` input, but do not record the complete hardware revision, firmware, descriptor, and report transaction set required for a canonical fixture. Current `XboxOneBluetoothHIDDescriptor.seriesDescriptor` is explicitly labelled an Xbox Series descriptor; tests comparing that constant are not a captured `0b0c` fixture. The repository's `Tests/ProtocolPacketFixtures/ProtocolPacketFixtures.swift` has no `0b0c` capture. Do not relabel any of these as captured ABI evidence.
- **Community:** Community reverse-engineering repositories are classified as community evidence. Their current revisions, licenses, exact source symbols, and fixture corroboration were not reviewed in this source record because none is needed to establish the owner's direct API-break decision. No claim from them supports that decision, and no community code or report bytes were copied. Pin and review any such source before using its protocol claims in implementation; this remains a later protocol-evidence task, not evidence that the sources or licenses are clear.

The evidence classes used for this decision are official documentation, upstream source, community sources not relied upon, and an explicitly absent captured fixture. Repository search, synthetic packer tests, and old published names do not establish captured device behavior. A new source fact copied into code or a fixture still needs an exact revision, license review, symbol/capture origin, and a fixture that reproduces the claimed behavior. The pending Xbox profile requires a real `045e:0b0c` fixture before its descriptor or reports may be claimed as supported.

[1]: https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/hardware/input-hardware-interfaces?view=gdk-2604
[2]: https://developer.apple.com/documentation/gamecontroller/understanding-game-controller-backward-compatibility
[3]: https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/src/joystick/controller_list.h
[4]: https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/LICENSE.txt
[5]: https://github.com/torvalds/linux/blob/44696aa3a489d2baf58efa61b37833f100072bee/drivers/input/joystick/xpad.c

## Admission Policy

- Select Flydigi, GameSir, XID, XUSB, GIP, or another specialized parser only for an exact cataloged VID/PID, transport, and protocol variant.
- Keep uncataloged standards-compliant HID descriptor-driven and Generic HID. Never infer a vendor protocol from a brand, vendor ID, or nearby product ID.
- A historical device list can corroborate an identity but cannot admit it. `0E4C:3240` and `FFFF:FFFF` remain unadmitted.
- Derive physical output capabilities from the selected parser. Protocol byte fixtures establish source-backed behavior; hardware verification requires a matching physical run.

## Pinned XID and XUSB Evidence

- [Xbox360Controller `9aa224a`][6]: [`Controller.cpp`][7], [`ControlStruct.h`][8], and [`LICENSE`][9] are the licensed implementation reference for original-Xbox input and rumble framing. OJD's encoder is independent and covered by byte fixtures.
- [Xb2XInput `8f4187a`][10]: [`README.md`][11], [`XboxController.hpp`][12], and [`XboxController.cpp`][13] corroborate XID framing and historical IDs only; they are not implementation or admission authority.
- [ViGEmBus `d986e1d`][14]: [`README.md`][15] and [`sys/XusbPdo.cpp`][16] describe a virtual XUSB target, not physical admission.
- [VDX `fb11124`][17]: [`README.md`][18] and [`src/Main.cpp`][19] demonstrate input mirroring to selected virtual output.
- [XInputHooker `f31d644`][20]: [`README.md`][21], [`XUSB.h`][22], and [`XInputHooker.cpp`][23] describe Windows XUSB discovery and IOCTL capture, not an OJD route.

[6]: https://github.com/xdccrlz/Xbox360Controller/tree/9aa224a89732cc42d2955762b47d8a5a281de75f
[7]: https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/Controller.cpp
[8]: https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/ControlStruct.h
[9]: https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/LICENSE
[10]: https://github.com/emoose/Xb2XInput/tree/8f4187a23ecd834961151fb68b7a17334820986b
[11]: https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/README.md
[12]: https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.hpp
[13]: https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.cpp
[14]: https://github.com/nefarius/ViGEmBus/tree/d986e1d93708ec9b11049542fa6027272cce716c
[15]: https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/README.md
[16]: https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/sys/XusbPdo.cpp
[17]: https://github.com/nefarius/VDX/tree/fb11124017f499adcc7c129822aef9bec80d3174
[18]: https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/README.md
[19]: https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/src/Main.cpp
[20]: https://github.com/nefarius/XInputHooker/tree/f31d64470831ac39644dc088e632898afa4dd926
[21]: https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/README.md
[22]: https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XUSB.h
[23]: https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XInputHooker.cpp

## Pinned GIP Evidence

- **Official:** Microsoft's [MS-GIPUSB] Gaming Input Protocol USB Extension, v20240916 (Release: September 16, 2024; the PDF hashed SHA-256 `7c5422b3ed04f7eb9ec453a047919ae46d2220bd7676889cbac07cecd080baa9`), defines the header flags (Table 14: bit 7 Fragment, 6 InitFrag, 5 System, 4 ACME, 3 reserved, 2:0 expansion index), the sequence pools (2.2.10.3: system commands share one pool; security, extended commands, audio and each vendor message type have their own; `0x00` is reserved), the fragment header field (3.1.5.2: total length in the first fragment, offset in later ones), the Xbox button key code `0x5B` (Table 2), the Direct Motor Command (Table 56: bit 0 right vibration, 1 left vibration, 2 right impulse, 3 left impulse; levels `0x00...0x64`) and the input report (Table 57).
  The PDF is not in the repository; no text is copied.
- **Upstream:** SDL's [`SDL_hidapi_gip.c` at `8adc0f98837db84fd24f17c339e59dcf36a17156`][24] corroborates the ACK body (`GIP_Acknowledge`: control code, command, the command's System flag, bytes received as a 32-bit offset, bytes remaining), the `0x5B` check (`GIP_HandleCommandGuideButtonStatus`) and levels in `0...100` (`HIDAPI_DriverGIP_RumbleJoystick`, division by 655). SDL's license is the one of row [4]. No SDL code is copied.
- **Upstream:** xpadneo's [`xpadneo.h` at `547eb90cd9f01de64db888b558f7e1a606c71965`][25] (`GPL-2.0-only`) gives the same four motor bits for the Xbox Series Bluetooth rumble report (`enum xpadneo_rumble_motors`). No xpadneo code is copied.
- **Tests:** `GIPDriverTests` (sequence pools, ACK bytes, fragment ACKs, Guide key code, motor levels), `GIPStartupPacketBytesTests` and `ConsumerOutputCodecTests.eachActivationBitEnablesOnlyItsMotor`.

[24]: https://github.com/libsdl-org/SDL/blob/8adc0f98837db84fd24f17c339e59dcf36a17156/src/joystick/hidapi/SDL_hidapi_gip.c
[25]: https://github.com/atar-axis/xpadneo/blob/547eb90cd9f01de64db888b558f7e1a606c71965/hid-xpadneo/src/xpadneo/xpadneo.h

## Pinned Flydigi Evidence

- **Community:** [`flydigi-space-station-mac`, `docs/protocol.md` at `649b9f36cbba80deb7e7ac11309615d44f382a8e`][26] (MIT, Copyright (c) 2026 Uilton Lopes and contributors; the notice is in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)) gives the Apex 4 DInput interface (`04B4:2412`, usage page `0xFFA0`, input report 4, output report 5) and the byte and bit layout of its report 4 (section 9). The notes say they were verified on an Apex 4; OJD has no capture of its own, so the `04B4:2412` record is source-derived and unverified. No code is copied.

- **Community:** [`openflydigi`, `PROTOCOL.md` at `11653507bbe4dc77f3c479c2a7aaebf25bbda995`][27] (repository `mkaliaha/openflydigi`; the file is dedicated under CC0 1.0, and the repository's other files are not covered by that dedication). Facts used: the frame `5A A5 cmd len payload sum8` on the `0xFFA0` node, the payloads of commands 18, 81 and 82, and the statement that those three commands set no checksum and that a pad accepts them without one. It gives no bit layout for bytes 11 to 14 of the `5A A5 EF` report. The repository's `flydigi/` and `tools/` code is MIT; `flydigi/device.py:244-253` and `flydigi/effects.py:339-387` were read for the frames of commands 18, 81 and 82, and no code was copied.

[26]: https://github.com/uiltonlopes/flydigi-space-station-mac/blob/649b9f36cbba80deb7e7ac11309615d44f382a8e/docs/protocol.md
[27]: https://github.com/mkaliaha/openflydigi/blob/11653507bbe4dc77f3c479c2a7aaebf25bbda995/PROTOCOL.md

## Current Evidence Boundaries

- [ControllerSources.lock.json](../../ControllerSources.lock.json) pins Linux commit `44696aa3a489d2baf58efa61b37833f100072bee` and per-file hashes for `xpad.c`, `hid-playstation.c`, `hid-sony.c`, `hid-nintendo.c`, and `hid-steam.c`. These upstream references establish protocol or identity context, not macOS descriptors, endpoints, TCC behavior, or hardware success. This record reviews the `xpad.c` SPDX identifier only; the other files support separate physical protocol work and were not license-reviewed here.
- GameSir `3537` records combine exact Linux identities with [`gamesir-linux-tools`](https://github.com/broroeror/gamesir-linux-tools/blob/main/RESEARCH.md) packet research. Shared Microsoft Bluetooth IDs are not attributed to GameSir without exact captures.
- [Issue 33](https://github.com/xsyetopz/OpenJoystickDriver/issues/33) verifies SCUF Envision Pro `2E95:434D` report-6 core input only. It does not establish extra buttons, paddles, output, or wireless behavior; `2E95:0504` stays GIP.
- SDL HIDAPI and mappings inform consumer identity and button order only.

## Gates

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd check profiles
./Scripts/ojd check schemas
./Scripts/ojd test parsers-macos14
swift test
```

Before adding transport or output, record lifecycle, framing, ownership, failure behavior, protocol fixtures, and a separate hardware plan. Before adding a spoof identity, record the exact descriptor, report bytes, and consumer.
