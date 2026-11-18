# Compatibility Source Notes

External projects give design or protocol evidence, not runtime dependencies or Mac hardware proof. SDL discussions: [#11002](https://github.com/libsdl-org/SDL/issues/11002), [#15663](https://github.com/libsdl-org/SDL/issues/15663), [#15790](https://github.com/libsdl-org/SDL/issues/15790), and [#15183](https://github.com/libsdl-org/SDL/pull/15183).

## Source, License, and Capture Boundaries

The approved compatibility break is an owner decision. These sources give only the stated evidence, authorize no additional OJD output profiles, prove no Mac ABI, and no code is copied from any.

| Kind | Source | Evidence and limits |
| --- | --- | --- |
| Official | Microsoft [GameInput device types (GDK 2604)](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/hardware/input-hardware-interfaces?view=gdk-2604) | Distinguishes generic HID from XUSB, XInputHID, GIP. Does not specify the 045e:0b0c descriptor and report ABI of OJD's proposed profile |
| Official | Apple [controller backward compatibility](https://developer.apple.com/documentation/gamecontroller/understanding-game-controller-backward-compatibility) | Describes a framework feature. Does not specify the 045e:0b0c ABI |
| Upstream | SDL [controller_list.h](https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/src/joystick/controller_list.h) | Lists 045e:0b0c as the Xbox Adaptive Controller over Bluetooth; `SDL_IsJoystickBluetoothXboxOne` (`src/joystick/SDL_joystick.c:3166-3181`) names it |
| Upstream | SDL HIDAPI Xbox One driver (`src/joystick/hidapi/SDL_hidapi_xboxone.c:370-379`) | Treats the virtual device as USB GIP, since the macOS transport is Virtual |
| Upstream | Apple `AppleGameControllerPersonality.kext` | Lists 045e:0b0c without `GCIOMatchVirtual`, so GameController does not bind it (`GameControllerPersonalityMatchTests`) |
| Upstream | SDL [LICENSE.txt, same commit](https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/LICENSE.txt) | Three-condition permissive license. The identity row supports consumer classification only |
| Upstream | Linux [xpad.c](https://github.com/torvalds/linux/blob/44696aa3a489d2baf58efa61b37833f100072bee/drivers/input/joystick/xpad.c), pinned by the source lock (SHA-256 `c24c86cbb74e74eba751e50899f3137ef0439e0d2a2c391a2e7c7d7556e87278`, in [ControllerSources.lock.json](../../ControllerSources.lock.json)) | Header gives GPL-2.0-or-later. Protocol-family context, not macOS publication evidence |
| Captured | `docs/testing/consumer-binding.md`, `docs/testing/haptics-backends.md` | User-reported observations, including failed 02fd input; no hardware revision, firmware, descriptor, or report transactions |
| Captured | `XboxOneBluetoothHIDDescriptor.seriesDescriptor` | Xbox Series descriptor; tests using it are not a 0b0c fixture |
| Captured | `Tests/ProtocolPacketFixtures/ProtocolPacketFixtures.swift` | No 0b0c capture |
| Community | Reverse-engineering repositories | Not relied upon; revisions, licenses, and symbols not reviewed |

No committed genuine 045e:0b0c descriptor or report capture exists; none of the captured rows is ABI evidence. Unpinned consumer and community references need review first.

Repository search, synthetic packer tests, and old published names do not establish captured device behavior. A source fact copied into code or a fixture needs an exact revision, license review, symbol or capture origin, and a reproducing fixture. The pending Xbox profile needs a real 045e:0b0c fixture before its descriptor or reports count as supported.

## Admission Policy

| Rule | Detail |
| --- | --- |
| Specialized parser | Flydigi, GameSir, XID, XUSB, GIP only for an exact cataloged VID/PID, transport, and protocol variant |
| Uncataloged standards-compliant HID | Stays descriptor-driven Generic HID. Never infer a vendor protocol from a brand, vendor ID, or nearby product ID |
| Historical device list | Corroborates an identity, cannot admit it. 0E4C:3240 and FFFF:FFFF stay unadmitted |
| Physical output | Derive capabilities from the selected parser. Byte fixtures establish source-backed behavior; hardware verification needs a physical run |

## Pinned XID and XUSB Evidence

| Project | Files | Use |
| --- | --- | --- |
| [Xbox360Controller 9aa224a](https://github.com/xdccrlz/Xbox360Controller/tree/9aa224a89732cc42d2955762b47d8a5a281de75f) | [Controller.cpp](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/Controller.cpp), [ControlStruct.h](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/ControlStruct.h), [LICENSE](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/LICENSE) | Licensed reference for original-Xbox input and rumble framing; OJD's encoder is independent, with byte fixtures |
| [Xb2XInput 8f4187a](https://github.com/emoose/Xb2XInput/tree/8f4187a23ecd834961151fb68b7a17334820986b) | [README.md](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/README.md), [XboxController.hpp](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.hpp), [XboxController.cpp](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.cpp) | Corroborates XID framing and historical IDs only |
| [ViGEmBus d986e1d](https://github.com/nefarius/ViGEmBus/tree/d986e1d93708ec9b11049542fa6027272cce716c) | [README.md](https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/README.md), [sys/XusbPdo.cpp](https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/sys/XusbPdo.cpp) | Describes a virtual XUSB target only |
| [VDX fb11124](https://github.com/nefarius/VDX/tree/fb11124017f499adcc7c129822aef9bec80d3174) | [README.md](https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/README.md), [src/Main.cpp](https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/src/Main.cpp) | Demonstrates input mirroring to virtual output |
| [XInputHooker f31d644](https://github.com/nefarius/XInputHooker/tree/f31d64470831ac39644dc088e632898afa4dd926) | [README.md](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/README.md), [XUSB.h](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XUSB.h), [XInputHooker.cpp](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XInputHooker.cpp) | Describes Windows XUSB discovery and IOCTL capture only |

## Pinned GIP Evidence

Official: Microsoft's [MS-GIPUSB] Gaming Input Protocol USB Extension, v20240916 (September 16, 2024; PDF SHA-256 `7c5422b3ed04f7eb9ec453a047919ae46d2220bd7676889cbac07cecd080baa9`; not in the repository) defines:

| Item | Reference | Definition |
| --- | --- | --- |
| Header flags | Table 14 | Bit 7 Fragment, 6 InitFrag, 5 System, 4 ACME, 3 reserved, 2:0 expansion index |
| Sequence pools | 2.2.10.3 | System commands share one pool; security, extended commands, audio, and each vendor message type have their own; `0x00` reserved |
| Fragment header field | 3.1.5.2 | Total length in the first fragment, offset in later ones |
| Xbox button key code | Table 2 | `0x5B` |
| Direct Motor Command | Table 56 | Bit 0 right vibration, 1 left vibration, 2 right impulse, 3 left impulse; levels `0x00...0x64` |
| Input report | Table 57 | |

| Kind | Source | Evidence |
| --- | --- | --- |
| Upstream | SDL [SDL_hidapi_gip.c](https://github.com/libsdl-org/SDL/blob/8adc0f98837db84fd24f17c339e59dcf36a17156/src/joystick/hidapi/SDL_hidapi_gip.c), SDL license | ACK body (`GIP_Acknowledge`: control code, command, System flag, 32-bit bytes-received offset, bytes remaining); `0x5B` check (`GIP_HandleCommandGuideButtonStatus`); levels `0...100` (`HIDAPI_DriverGIP_RumbleJoystick`, division by 655) |
| Upstream | xpadneo [xpadneo.h](https://github.com/atar-axis/xpadneo/blob/547eb90cd9f01de64db888b558f7e1a606c71965/hid-xpadneo/src/xpadneo/xpadneo.h), GPL-2.0-only | Same four motor bits for Xbox Series Bluetooth rumble (`enum xpadneo_rumble_motors`) |
| Tests | | `GIPDriverTests`, `GIPStartupPacketBytesTests`, `ConsumerOutputCodecTests.eachActivationBitEnablesOnlyItsMotor` |

## Pinned Flydigi Evidence

| Source | License | Used |
| --- | --- | --- |
| Community: [flydigi-space-station-mac, docs/protocol.md](https://github.com/uiltonlopes/flydigi-space-station-mac/blob/649b9f36cbba80deb7e7ac11309615d44f382a8e/docs/protocol.md) | MIT, Uilton Lopes and contributors; notice in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) | Apex 4 DInput interface (04B4:2412, usage page `0xFFA0`, input report 4, output report 5); report 4 byte and bit layout (section 9), which the notes say an Apex 4 verified |
| Community: [openflydigi, PROTOCOL.md](https://github.com/mkaliaha/openflydigi/blob/11653507bbe4dc77f3c479c2a7aaebf25bbda995/PROTOCOL.md) (`mkaliaha/openflydigi`) | File CC0 1.0, other files not; `flydigi/` and `tools/` code MIT | Frame `5A A5 cmd len payload sum8` on the `0xFFA0` node; payloads of commands 18, 81, 82 (read `flydigi/device.py:244-253`, `flydigi/effects.py:339-387`) |

OJD has no capture: the 04B4:2412 record is source-derived and unverified. Commands 18, 81, 82 set no checksum; a pad accepts them without one. The file gives no bit layout for bytes 11 to 14 of the `5A A5 EF` report.

## Current Evidence Boundaries

| Source | Evidence and limits |
| --- | --- |
| [ControllerSources.lock.json](../../ControllerSources.lock.json) | Pins Linux commit `44696aa3a489d2baf58efa61b37833f100072bee` and per-file hashes for `xpad.c`, `hid-playstation.c`, `hid-sony.c`, `hid-nintendo.c`, `hid-steam.c`. Protocol or identity context, not macOS descriptors, endpoints, TCC behavior, or hardware success. Only the `xpad.c` SPDX identifier was reviewed |
| GameSir 3537 records | Exact Linux identities plus [gamesir-linux-tools](https://github.com/broroeror/gamesir-linux-tools/blob/main/RESEARCH.md) packet research. Shared Microsoft Bluetooth IDs need exact captures before attribution to GameSir |
| [Issue 33](https://github.com/xsyetopz/OpenJoystickDriver/issues/33) | Verifies SCUF Envision Pro 2E95:434D report-6 core input only, not extra buttons, paddles, output, or wireless behavior. 2E95:0504 stays GIP |
| SDL HIDAPI and mappings | Consumer identity and button order only |

## Wii Remote Evidence

- [wiiuse `e769bd7`](https://github.com/wiiuse/wiiuse/tree/e769bd7) (GPL-3.0-or-later) corroborates Wii Remote register addresses, report ids, and sizes (link target not verified). WiiBrew's Wiimote pages are the primary protocol source. Every Wii fixture is a source fixture, not hardware evidence.

## Gates

```bash
just catalog-regenerate --check
just check-profiles
just check-schemas
just test-parsers-macos14
swift test
```

Before adding transport or output, record lifecycle, framing, ownership, failure behavior, fixtures, and a hardware plan. Before adding a spoof identity, record the exact descriptor, report bytes, and consumer.
