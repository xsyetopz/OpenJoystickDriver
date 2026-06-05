# Xbox Adaptive Joystick Packet Request

OJD needs exact standalone Xbox Adaptive Joystick evidence before adding a profile or parser. Microsoft documents direct PC compatibility and 7 physical buttons, but a repeated 2026-06-06 source search did not find authoritative standalone VID/PID, interface, endpoint, or packet bytes. Do not use Xbox Adaptive Controller VID/PID or accessory assumptions for this device.

## Current Public Source Status

Microsoft's product page confirms the Xbox Adaptive Joystick can plug directly into a console or PC, uses USB-C, and has 7 physical buttons. It does not publish standalone USB VID/PID, interface, endpoint, or packet bytes. A public Reddit comment shows an example Windows Device Manager path `USB\VID_045E&PID_0B1A\...` for a directly connected adaptive joystick, but that is not authoritative enough for OJD to add a committed profile without tester confirmation. Treat any prefilled `0x045e` / `0x0b1a` values as hints to verify, not source of truth.

## Required Device Identity

Record these with the joystick plugged directly into the Mac by USB-C:

- macOS version
- OJD commit, if OJD is running
- USB vendor ID and product ID in decimal and hex
- product string, manufacturer string, serial string if exposed
- interface number, class, subclass, protocol
- endpoint addresses and max packet sizes, if visible
- whether macOS exposes it as HID, vendor-specific USB, or both

Useful macOS commands:

```bash
system_profiler SPUSBDataType
ioreg -p IOUSB -l -w0
ioreg -r -c IOHIDDevice -l -w0
```

## Required Packet Captures

Capture raw packets for each state below. Keep one action changed at a time and return to neutral between captures.

- neutral, untouched
- stick full left
- stick full right
- stick full up
- stick full down
- stick center after each extreme
- stick click pressed and released
- X1 pressed and released
- X2 pressed and released
- X3 pressed and released
- X4 pressed and released
- X5 pressed and released
- X6 pressed and released
- any mode/profile/remap state that changes the report

For each packet, include:

- capture label
- raw hex bytes exactly as captured
- report ID, if one is present
- packet length
- transport used by the capture tool: HID input report or raw USB interrupt transfer
- notes for any byte/bit annotation you can infer

## OJD Packet Capture Paths

If macOS exposes the joystick through IOHID, build and run the OJD HID monitor with the exact VID/PID from the identity step:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x045e --pid 0x0000 --seconds 20
```

Replace `0x045e` and `0x0000` with the observed vendor and product IDs. For each labeled action, paste the `REPORT ... bytes=...` line and any changed `VALUE`/`POLL` lines. The `REPORT bytes=` value is preferred for HID parser tests because it preserves the raw HID input report bytes that OJD will need to parse.

If the HID path does not emit reports or the tester wants the requested raw USB capture, first run the raw USB interrupt monitor without `--endpoint`. OJD will sweep interrupt IN endpoint candidates `0x81...0x8f` and print either `USB_REPORT` lines or per-endpoint `USB_ENDPOINT ... result=error` lines:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 0 --length 64 --seconds 20
```

If one endpoint produces reports, repeat the capture with that exact endpoint while performing each labeled action:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 0 --endpoint 0x81 --length 64 --seconds 20
```

If libusb reports access denied or busy, retry with `--detach` and record that `--detach` was needed:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 0 --length 64 --seconds 20 --detach
```

For each labeled action, paste the `USB_REPORT endpoint=... len=... bytes=...` line. If no packets are captured, include the full `USB_MONITOR`, `USB_DEVICE`, `USB_CLAIM`, `USB_ENDPOINT_SWEEP`, `USB_ENDPOINT`, and `USB_SUMMARY` output so OJD can distinguish a permissions/endpoint issue from an unsupported layout.

If OJD detects the physical joystick through the app/daemon path, open the Input Test/Developer packet log and export or paste the recent RX entries after each labeled action. If neither OJD path can open it, use a separate HID/USB capture tool and include the identity details above.

## Minimum Test Set For Parser Work

A parser can start only after these are available:

- exact VID/PID
- neutral packet
- one packet for every button pressed independently
- stick X/Y min, max, and center packets
- report length and report ID behavior

Until then, OJD will keep Xbox Adaptive Joystick as planned experimental work without a committed profile, because guessing the standalone VID/PID or packet layout could route another Microsoft device incorrectly.
