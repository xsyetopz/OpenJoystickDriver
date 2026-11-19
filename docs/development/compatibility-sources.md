# Compatibility Source Notes

Other open-source projects, such as Linux drivers and SDL, already know how many controllers talk. OJD reads them to learn the facts. OJD doesn't run their code, and a fact from them still needs a test on a Mac. SDL discussions: [#11002](https://github.com/libsdl-org/SDL/issues/11002), [#15663](https://github.com/libsdl-org/SDL/issues/15663), [#15790](https://github.com/libsdl-org/SDL/issues/15790), and [#15183](https://github.com/libsdl-org/SDL/pull/15183).

## What Each Source Can and Can't Tell Us

The project owner decided on the approved compatibility break. These sources only back up what each row says. None of them allows OJD to add more output profiles, none proves the exact bytes a Mac sees (the ABI), and OJD copies no code from any of them.

| Kind | Source | What it shows, and its limits |
| --- | --- | --- |
| Official | Microsoft [GameInput device types (GDK 2604)](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/hardware/input-hardware-interfaces?view=gdk-2604) | Tells generic HID apart from XUSB, XInputHID, and GIP. Doesn't give the 045e:0b0c descriptor or report bytes for OJD's planned profile |
| Official | Apple [controller backward compatibility](https://developer.apple.com/documentation/gamecontroller/understanding-game-controller-backward-compatibility) | Describes a framework feature. Doesn't give the 045e:0b0c bytes |
| Upstream | SDL [controller_list.h](https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/src/joystick/controller_list.h) | Lists 045e:0b0c as the Xbox Adaptive Controller over Bluetooth; `SDL_IsJoystickBluetoothXboxOne` (`src/joystick/SDL_joystick.c:3166-3181`) names it |
| Upstream | SDL HIDAPI Xbox One driver (`src/joystick/hidapi/SDL_hidapi_xboxone.c:370-379`) | Treats the virtual device as USB GIP, because macOS reports its connection as Virtual |
| Upstream | Apple `AppleGameControllerPersonality.kext` | Lists 045e:0b0c without `GCIOMatchVirtual`, so GameController does not bind it (`GameControllerPersonalityMatchTests`) |
| Upstream | SDL [LICENSE.txt, same commit](https://github.com/libsdl-org/SDL/blob/fa2c02bb6e21974a89ea9824bc53c9932abe5f9c/LICENSE.txt) | A permissive license with three conditions. The identity row only helps say how apps will see the pad |
| Upstream | Linux [xpad.c](https://github.com/torvalds/linux/blob/44696aa3a489d2baf58efa61b37833f100072bee/drivers/input/joystick/xpad.c), pinned by the source lock (SHA-256 `c24c86cbb74e74eba751e50899f3137ef0439e0d2a2c391a2e7c7d7556e87278`, in [ControllerSources.lock.json](../../ControllerSources.lock.json)) | The header says GPL-2.0-or-later. Background on the protocol family, not proof of how macOS publishes it |
| Captured | `docs/testing/consumer-binding.md`, `docs/testing/haptics-backends.md` | What users reported, including 02fd input that failed. No hardware revision, firmware, descriptor, or report exchanges |
| Captured | `XboxOneBluetoothHIDDescriptor.seriesDescriptor` | Xbox Series descriptor. Tests that use it aren't 0b0c test data |
| Captured | `Tests/ProtocolPacketFixtures/ProtocolPacketFixtures.swift` | No 0b0c capture |
| Community | Reverse-engineering repositories | Not used. Nobody reviewed their versions, licenses, or symbols |

The repository has no descriptor or report capture from a real 045e:0b0c, and none of the captured rows proves its bytes. App and community sources that aren't pinned to a version need review first.

Searching the repository, tests built from made-up packets, and old published names don't show how a real device behaves. Before a fact from a source goes into code or test data, it needs:

- the exact version of the source
- a license review
- where it came from (a symbol name or a capture)
- test data that shows the same thing

The planned Xbox profile needs test data from a real 045e:0b0c before its descriptor or reports count as supported.

## Rules for Adding a Controller

| Rule | Detail |
| --- | --- |
| Special parser | Flydigi, GameSir, XID, XUSB, or GIP, only for an exact VID/PID, connection, and protocol variant in the catalog |
| Standard HID pad not in the catalog | Stays on Generic HID, read from its descriptor. Never guess a vendor protocol from a brand, vendor ID, or a product ID close by |
| Old device lists | Back up an identity, but can't add it on their own. 0E4C:3240 and FFFF:FFFF stay out |
| Rumble and lights | What's offered comes from the chosen parser. Byte tests show what the sources say. Confirming it on hardware needs a run on a real pad |

## Pinned XID and XUSB Sources

| Project | Files | Use |
| --- | --- | --- |
| [Xbox360Controller 9aa224a](https://github.com/xdccrlz/Xbox360Controller/tree/9aa224a89732cc42d2955762b47d8a5a281de75f) | [Controller.cpp](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/Controller.cpp), [ControlStruct.h](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/360Controller/ControlStruct.h), [LICENSE](https://github.com/xdccrlz/Xbox360Controller/blob/9aa224a89732cc42d2955762b47d8a5a281de75f/LICENSE) | Licensed reference for original-Xbox input and rumble packets. OJD's encoder is written separately, with byte tests |
| [Xb2XInput 8f4187a](https://github.com/emoose/Xb2XInput/tree/8f4187a23ecd834961151fb68b7a17334820986b) | [README.md](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/README.md), [XboxController.hpp](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.hpp), [XboxController.cpp](https://github.com/emoose/Xb2XInput/blob/8f4187a23ecd834961151fb68b7a17334820986b/Xb2XInput/XboxController.cpp) | Only backs up XID packets and old IDs |
| [ViGEmBus d986e1d](https://github.com/nefarius/ViGEmBus/tree/d986e1d93708ec9b11049542fa6027272cce716c) | [README.md](https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/README.md), [sys/XusbPdo.cpp](https://github.com/nefarius/ViGEmBus/blob/d986e1d93708ec9b11049542fa6027272cce716c/sys/XusbPdo.cpp) | Describes a virtual XUSB target only |
| [VDX fb11124](https://github.com/nefarius/VDX/tree/fb11124017f499adcc7c129822aef9bec80d3174) | [README.md](https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/README.md), [src/Main.cpp](https://github.com/nefarius/VDX/blob/fb11124017f499adcc7c129822aef9bec80d3174/src/Main.cpp) | Shows input copied to a virtual output |
| [XInputHooker f31d644](https://github.com/nefarius/XInputHooker/tree/f31d64470831ac39644dc088e632898afa4dd926) | [README.md](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/README.md), [XUSB.h](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XUSB.h), [XInputHooker.cpp](https://github.com/nefarius/XInputHooker/blob/f31d64470831ac39644dc088e632898afa4dd926/XInputHooker/XInputHooker.cpp) | Describes Windows XUSB discovery and IOCTL capture only |

## Pinned GIP Sources

Official: Microsoft's [MS-GIPUSB] Gaming Input Protocol USB Extension, v20240916 (September 16, 2024; PDF SHA-256 `7c5422b3ed04f7eb9ec453a047919ae46d2220bd7676889cbac07cecd080baa9`; not in the repository) defines:

| Item | Reference | Definition |
| --- | --- | --- |
| Header flags | Table 14 | Bit 7 Fragment, 6 InitFrag, 5 System, 4 ACME, 3 reserved, 2:0 expansion index |
| Sequence pools | 2.2.10.3 | System commands share one pool; security, extended commands, audio, and each vendor message type have their own; `0x00` reserved |
| Fragment header field | 3.1.5.2 | Total length in the first fragment, offset in later ones |
| Xbox button key code | Table 2 | `0x5B` |
| Direct Motor Command | Table 56 | Bit 0 right vibration, 1 left vibration, 2 right impulse, 3 left impulse; levels `0x00...0x64` |
| Input report | Table 57 | |

| Kind | Source | What it shows |
| --- | --- | --- |
| Upstream | SDL [SDL_hidapi_gip.c](https://github.com/libsdl-org/SDL/blob/8adc0f98837db84fd24f17c339e59dcf36a17156/src/joystick/hidapi/SDL_hidapi_gip.c), SDL license | ACK body (`GIP_Acknowledge`: control code, command, System flag, 32-bit bytes-received offset, bytes remaining); `0x5B` check (`GIP_HandleCommandGuideButtonStatus`); levels `0...100` (`HIDAPI_DriverGIP_RumbleJoystick`, division by 655) |
| Upstream | xpadneo [xpadneo.h](https://github.com/atar-axis/xpadneo/blob/547eb90cd9f01de64db888b558f7e1a606c71965/hid-xpadneo/src/xpadneo/xpadneo.h), GPL-2.0-only | Same four motor bits for Xbox Series Bluetooth rumble (`enum xpadneo_rumble_motors`) |
| Tests | | `GIPDriverTests`, `GIPStartupPacketBytesTests`, `ConsumerOutputCodecTests.eachActivationBitEnablesOnlyItsMotor` |

## Pinned Flydigi Sources

| Source | License | Used |
| --- | --- | --- |
| Community: [flydigi-space-station-mac, docs/protocol.md](https://github.com/uiltonlopes/flydigi-space-station-mac/blob/649b9f36cbba80deb7e7ac11309615d44f382a8e/docs/protocol.md) | MIT, Uilton Lopes and contributors; notice in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) | Apex 4 DInput interface (04B4:2412, usage page `0xFFA0`, input report 4, output report 5); report 4 byte and bit layout (section 9), which the notes say an Apex 4 verified |
| Community: [openflydigi, PROTOCOL.md](https://github.com/mkaliaha/openflydigi/blob/11653507bbe4dc77f3c479c2a7aaebf25bbda995/PROTOCOL.md) (`mkaliaha/openflydigi`) | File CC0 1.0, other files not; `flydigi/` and `tools/` code MIT | Frame `5A A5 cmd len payload sum8` on the `0xFFA0` node; payloads of commands 18, 81, 82 (read `flydigi/device.py:244-253`, `flydigi/effects.py:339-387`) |

OJD has no capture, so the 04B4:2412 record comes only from these sources and isn't confirmed. Commands 18, 81, 82 set no checksum, and a pad accepts them without one. The file gives no bit layout for bytes 11 to 14 of the `5A A5 EF` report.

## Limits of Other Sources

| Source | What it shows, and its limits |
| --- | --- |
| [ControllerSources.lock.json](../../ControllerSources.lock.json) | Pins Linux commit `44696aa3a489d2baf58efa61b37833f100072bee` and per-file hashes for `xpad.c`, `hid-playstation.c`, `hid-sony.c`, `hid-nintendo.c`, `hid-steam.c`. Background on protocols and identities, not macOS descriptors, endpoints, TCC behavior, or proof it works on hardware. Only the `xpad.c` SPDX license tag was reviewed |
| GameSir 3537 records | Exact Linux identities plus [gamesir-linux-tools](https://github.com/broroeror/gamesir-linux-tools/blob/main/RESEARCH.md) packet research. Microsoft Bluetooth IDs that other pads share need exact captures before they're credited to GameSir |
| [Issue 33](https://github.com/xsyetopz/OpenJoystickDriver/issues/33) | Confirms only the main report-6 input of the SCUF Envision Pro 2E95:434D, not extra buttons, paddles, output, or wireless behavior. 2E95:0504 stays GIP |
| SDL HIDAPI and mappings | Only how apps identify the pad, and button order |

## Wii Remote Sources

- [wiiuse `e769bd7`](https://github.com/wiiuse/wiiuse/tree/e769bd7) (GPL-3.0-or-later) backs up Wii Remote register addresses, report ids, and sizes (nobody checked the link target). WiiBrew's Wiimote pages are the main protocol source. All Wii test data comes from sources, not from hardware.

## Checks to Run

```bash
just catalog-regenerate --check
just check-profiles
just check-schemas
just test-parsers-macos14
swift test
```

Before adding a connection type or output, write down: when it starts and stops, the packet layout, who owns the device, what happens on failure, test data, and a plan for testing on hardware. Before adding an identity that poses as another controller, write down the exact descriptor, report bytes, and the app that reads it.
