# Capture Xbox Adaptive Joystick packets

OJD should not add a standalone Xbox Adaptive Joystick record until we have the actual USB identity and packets from the device plugged directly into a Mac.

Microsoft documents direct PC use, USB-C, and 7 physical buttons. It does not publish the standalone VID/PID, interface, endpoint, or report bytes. A public Reddit comment mentions `USB\VID_045E&PID_0B1A\...`, but OJD needs tester output before committing a record.

## What To Send Back

Useful output is better than perfect output. If a command fails, paste the full failure. That tells us whether the next step is HID parsing, raw USB, or DriverKit.

Please include:

- macOS version
- OJD version or commit, if used
- whether the joystick is plugged directly into the Mac by USB-C
- exact commands you ran
- full output from commands that found no device or no packets
- any byte notes you already know

## 1. macOS Native Checks

Plug the joystick directly into the Mac. Run:

```bash
system_profiler SPUSBDataType
ioreg -p IOUSB -l -w0
ioreg -r -c IOHIDDevice -l -w0
```

Paste the entries that mention Xbox, Microsoft, Adaptive, joystick, gamepad, or `045e`. If no obvious entry appears, unplug the joystick, run the commands again, and paste the entries that disappeared.

Record these fields if visible:

- vendor ID and product ID in hex and decimal
- product, manufacturer, and serial strings
- interface number
- class, subclass, and protocol
- endpoint addresses and max packet sizes
- whether macOS exposes it as HID, raw USB, or both

## 2. OJD Device Listing

From the repository root:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --list
```

Paste any `VID:0x45e` or Microsoft-looking lines. If the joystick appears under a different VID/PID, use that exact pair in the commands below.

## 3. HID Monitor

If `--list` shows the joystick as an IOHID device, run the HID monitor with the observed VID/PID:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x045e --pid 0x0000 --seconds 30
```

Replace `0x0000` with the observed PID. Paste every `REPORT ... bytes=...`, `VALUE ...`, and `POLL ...` line. If the monitor prints `Monitoring 0 device(s)` or no reports, keep the full output and continue to raw USB.

## 4. Raw USB Monitor

Run a raw USB endpoint sweep with the observed VID/PID:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 0 --length 64 --seconds 20
```

If interface 0 produces no packets, try interface 1:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 1 --length 64 --seconds 20
```

If libusb reports access denied or busy, rerun the same command with `--detach` and paste both outputs.

If the sweep finds an endpoint, repeat with that endpoint while pressing one control at a time:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --interface 0 --endpoint 0x81 --length 64 --seconds 30
```

Replace the VID, PID, interface, and endpoint with the values from the sweep.

## 5. Packets To Capture

Return to neutral between captures. One changed control per packet is enough.

Capture:

- neutral, untouched
- stick full left, right, up, down, then center
- stick click press and release
- X1 press and release
- X2 press and release
- X3 press and release
- X4 press and release
- X5 press and release
- X6 press and release
- any mode, profile, or remap state that changes the packet

For each capture, paste:

- label
- `REPORT ... bytes=...` or `USB_REPORT ... bytes=...`
- report ID, if present
- packet length
- interface and endpoint, for raw USB
- any known byte or bit meaning

## 6. OJD App Check

If OJD sees the joystick in the app or application service path, open Input Test and use the packet log. For each action above, paste the recent RX entries and say whether the on-screen state changed.

If OJD cannot see it but macOS native tools can, say that. That points toward a DriverKit/raw USB path instead of a record-only fix.

## Minimum Parser Evidence

A parser can start after we have:

- exact VID/PID
- neutral packet
- one independent packet for every button
- stick X/Y min, max, and center packets
- report length
- report ID behavior, if any
- interface and endpoint for raw USB captures

## Paste-Back Template

```text
macOS version:
OJD version/commit:
Direct USB-C connection: yes/no

macOS native:
- system_profiler entry:
- ioreg IOUSB entry:
- ioreg IOHIDDevice entry:
- VID/PID observed:
- product/manufacturer/serial:
- interface/class/subclass/protocol:
- endpoints:

OJD listing:
- OpenJoystickDriverHIDTool --list sees joystick: yes/no, lines:

HID monitor:
- command:
- device count:
- REPORT lines captured: yes/no, excerpts:
- VALUE/POLL lines captured: yes/no, excerpts:

Raw USB:
- command:
- interface:
- endpoint:
- USB_REPORT lines captured: yes/no, excerpts:
- access denied/busy: yes/no
- --detach tried: yes/no, result:

Packet labels:
- neutral:
- stick left:
- stick right:
- stick up:
- stick down:
- stick center:
- stick click:
- X1:
- X2:
- X3:
- X4:
- X5:
- X6:

Known byte notes:
Unexpected behavior:
```
