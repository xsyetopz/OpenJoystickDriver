# Xbox fallback identities

A product name is not enough to create a safe spoof identity. Each selectable identity needs:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result;
4. hardware evidence for GameController.framework claims.

The consumer family is part of the identity contract: SDL/HIDAPI, Apple
GameController, XUSB generic HID, and generic HID are not interchangeable. A
successful enumeration or identity lookup never promotes a route to working.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

The full selection key is physical protocol family × target consumer family ×
evidence level. Normalized input is internal only; the published identity,
transport, descriptor, packer, and output tuple remains atomic. There is no
Xbox-to-PlayStation, Nintendo-to-Xbox, or PlayStation-to-Xbox shortcut.

## Evidence by family

### Xbox Wireless Controller

OJD does not ship a selectable Xbox One Bluetooth-shaped generic-HID spoof.
Earlier `045e:02fd` / BT1/BT2 experiments produced no usable SDL HIDAPI input and
were retired. Automatic GIP and `apple-gamecontroller` publish `045e:0b13`
"Xbox Wireless Controller". GameSir G7 SE USB GIP is hardware-verified for
GameController.framework. Physical GIP sends Hello plus one rest `0x20`, then
change-only input; a status-only packet log after that is not a failed
init. A custom SDL 3.4.16 HIDAPI xboxone build bound the
Bluetooth `045e:0b13` identity and used the 17-byte BLE path; a 12s
interrupt watch stayed idle (no physical button). Steam `hid_init` still
hangs. Explicit picker DualShock 4 / DualSense from that GIP pad returned
`GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`.
Use `generic-hid` when no specialized adjacent identity
applies.

### Xbox Wired Controller

OJD has several physical records and parsers but no distinct verified fallback identity. Promotion needs a live consumer result whose descriptor and reports OJD implements exactly.

### Xbox 360 Wireless Controller

Linux source lists receiver devices, and OJD parses the physical receiver transport. A virtual family identity still needs a descriptor, report contract, and live consumer evidence.

### Xbox 360 Wired Controller

The explicit `xbox360-hid` profile uses the OJD Xbox 360-family HID report
format and `045e:028e`-shaped USB identity. It is generic HID compatibility,
not Windows XUSB22.sys or XInput. The SDL `sdl2-3` profile uses the
same first-party Microsoft Xbox 360 Wired tuple. XUSB clones that
SDL HIDAPI does not list spoof that official identity. ASTRO C40 `9886:0024`
is a DualShock-style third-party pad and is not a spoof target, including for
GIP devices such as GameSir G7 SE.

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
descriptor/report/output evidence. Automatic routing substitutes first-party
Microsoft `045e:028e` for XUSB pads. It does not substitute ASTRO C40
for any physical family.

## Promotion checks

After recording the required identity evidence, verify that SDL and GameController probes identify a useful consumer. Hardware tests must cover input, reconnect, rumble, and lights where claimed.

Use `generic-hid` as the fallback when no specialized consumer profile applies.
Use `sdl2-3` only for XUSB SDL 2/3 consumers; it publishes first-party
Microsoft `045e:028e`, not ASTRO C40.
