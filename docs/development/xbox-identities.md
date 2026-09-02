# Xbox fallback identities

A product name is not enough to create a safe spoof identity. Each selectable identity needs:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result;
4. hardware evidence for GameController.framework claims.

The consumer family is part of the identity contract: SDL/HIDAPI, Apple
GameController, Xbox One-shaped generic HID, and generic HID are not interchangeable. A
successful enumeration or identity lookup never promotes a route to working.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

The full selection key is physical protocol family × target consumer family ×
evidence level. Normalized input is internal only; the published identity,
transport, descriptor, packer, and output tuple remains atomic. There is no
Xbox-to-PlayStation, Nintendo-to-Xbox, or PlayStation-to-Xbox shortcut.

## Evidence by family

### Xbox Wireless Controller

OJD has the source-backed `xone-hid` path at `045e:02fd`, matching the Xbox One
S Bluetooth identity, product name, Bluetooth transport metadata, descriptor,
input report, Guide report, and report-3 decoder. It remains subject to live
consumer and hardware checks.
The reported Xbox One Bluetooth BT1/BT2 attempts produced no usable SDL
HIDAPI input; record this as reported failure for SDL, while keeping Apple
GameController separately testable.

### Xbox Wired Controller

OJD has several physical records and parsers but no distinct verified fallback identity. Promotion needs a live consumer result whose descriptor and reports OJD implements exactly.

### Xbox 360 Wireless Controller

Linux source lists receiver devices, and OJD parses the physical receiver transport. A virtual family identity still needs a descriptor, report contract, and live consumer evidence.

### Xbox 360 Wired Controller

The explicit `xbox360-hid` profile uses the OJD Xbox 360-family HID report
format and `045e:028e`-shaped USB identity. It is generic HID compatibility,
not Windows XUSB or XInputHID emulation. The SDL-specific `sdl2-3` profile uses
ASTRO `9886:0024`. OJD implements the exact Xbox 360-style HIDAPI reports for
the ASTRO identity. That SDL route is hardware-verified for input and physical
rumble with the GameSir G7 SE. A signed live test on
2026-07-13 accepted the `045e:028e` virtual device through
`GCController.supportsHIDDevice` and exposed an extended controller, but those
observations do not establish input, reconnect, or haptics for the new tuple.
Those checks must be repeated on the target macOS/runtime.

ASTRO C40 PS4 mode `9886:0025` remains an experimental research candidate only;
the required complete descriptor, feature/calibration, input, and output
evidence is absent, so no supported spoof is provided.

## Apple audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. That result applies only to the audited system and asset version. Check again after macOS or MobileAsset updates:

```bash
OpenJoystickDriver --headless diagnose catalog --json
```

The developer CLI and support report use the same audit.

Automatic routing does not persist a consumer-derived identity. The explicit
`CompatibilityIdentity` is persisted under the `CompatibilityIdentity`
UserDefaults key; startup reads that value and reset removes it before
returning to `.automatic`. While `.automatic` is active, the runtime resolves
the current foreground consumer and may replace/retire its backend. It falls
back to Generic HID when no adjacent identity has the required
descriptor/report/output evidence. Automatic routing does not currently
substitute C40 for any physical family. The C40 Xbox-mode evidence remains an
explicit SDL/PCSX2/Steam-like route only; the GIP record is not evidence for an
automatic C40 substitution.

## Promotion checks

After recording the required identity evidence, verify that SDL and GameController probes identify a useful consumer. Hardware tests must cover input, reconnect, rumble, and lights where claimed.

Use `generic-hid` as the fallback when no specialized consumer profile applies.
Use `sdl2-3` only for SDL 2/3 consumers; its ASTRO HIDAPI implementation is the
verified replacement for the removed separate Xbox 360 HID profile.
