# Xbox fallback identities

A product name is not enough to create a safe spoof identity. Each selectable identity needs:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result;
4. hardware evidence for GameController.framework claims.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

## Evidence by family

### Xbox Wireless Controller

OJD has the experimental `xone-hid` path at `045e:02ea`. A GameSir G7 SE live
test published the identity without crashing PCSX2 Nightly, but input and
rumble did not work. It still lacks a usable live descriptor/runtime match.

### Xbox Wired Controller

OJD has several physical records and parsers but no distinct verified fallback identity. Promotion needs a live consumer result whose descriptor and reports OJD implements exactly.

### Xbox 360 Wireless Controller

Linux source lists receiver devices, and OJD parses the physical receiver transport. A virtual family identity still needs a descriptor, report contract, and live consumer evidence.

### Xbox 360 Wired Controller

`apple-gamecontroller` uses `045e:028e`; the SDL-specific `sdl2-3` profile uses
ASTRO `9886:0024`. OJD implements the exact Xbox 360-style HIDAPI reports for
the ASTRO identity. That SDL route is hardware-verified for input and physical
rumble with the GameSir G7 SE. A signed live test on
2026-07-13 accepted the `045e:028e` virtual device through
`GCController.supportsHIDDevice` and exposed an extended controller, but the
August 25 test exposed neither input nor a public haptics engine. That pair was
absent from the audited private catalog.

## Apple audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. That result applies only to the audited system and asset version. Check again after macOS or MobileAsset updates:

```bash
OpenJoystickDriver --headless diagnose catalog --json
```

The developer CLI and support report use the same audit.

## Promotion checks

After recording the required identity evidence, verify that SDL and GameController probes identify a useful consumer. Hardware tests must cover input, reconnect, rumble, and lights where claimed.

Use `generic-hid` as the fallback when no specialized consumer profile applies.
Use `sdl2-3` only for SDL 2/3 consumers; its ASTRO HIDAPI implementation is the
verified replacement for the removed separate Xbox 360 HID profile.
