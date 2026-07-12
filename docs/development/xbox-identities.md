# Xbox fallback identities

A product name is not enough to create a safe spoof identity. Each selectable identity needs:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. an Apple GameController catalog match or live `GCController.supportsHIDDevice` result.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

## Evidence by family

### Xbox Wireless Controller

OJD has the experimental `xone-hid` path at `045e:02ea`. It still lacks an exact Apple catalog entry and a live descriptor/runtime match.

### Xbox Wired Controller

OJD has several physical records and parsers but no distinct Apple-backed fallback identity. Promotion needs one Apple-listed identity whose descriptor and reports OJD implements exactly.

### Xbox 360 Wireless Controller

Linux source lists receiver devices, and OJD parses the physical receiver transport. A virtual family identity still needs a descriptor, report contract, and Apple evidence.

### Xbox 360 Wired Controller

`apple-gamecontroller` uses `045e:028e`; `x360-hid` uses ASTRO `9886:0024`. OJD implements Xbox 360-style reports, but neither spoof VID/PID had an exact match in the audited Apple asset.

## Apple audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. That result applies only to the audited system and asset version. Check again after macOS or MobileAsset updates:

```bash
OpenJoystickDriver --headless diagnose gamecontroller-catalog --json
```

The CLI, menu app, and support report use the same audit.

## Promotion checks

Add a family identity only after the exact Apple evidence, descriptor, and report bytes are recorded. Browser, SDL, and GameController probes must identify a useful consumer. Hardware tests must cover input, reconnect, rumble, and lights where claimed.

Use `generic-hid` as the non-spoof fallback and `sdl2-3` as the default mapped identity until those checks pass.
