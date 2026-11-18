# Capture Xbox Adaptive Joystick Packets

OJD needs the USB identity and packets of an Xbox Adaptive Joystick connected directly to a Mac before adding a record.

Microsoft documents direct PC use, USB-C, 7 physical buttons, not the standalone VID/PID, interface, endpoint, or report bytes. A public Reddit comment mentions `USB\VID_045E&PID_0B1A\...`. No record until tester output.

## What to Send Back

Fill in the [form](#paste-back-report-form). Paste full output of failed commands and commands finding no device or packets; it shows whether HID, raw USB, or DriverKit comes next.

## 1. macOS Native Checks

1. Plug the joystick directly into the Mac; run:

   ```bash
   system_profiler SPUSBDataType
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOHIDDevice -l -w0
   ```

2. Paste entries mentioning Xbox, Microsoft, Adaptive, joystick, gamepad, or `045e`. If none, unplug, rerun, paste the entries that disappeared.
3. Record, if visible: vendor and product ID (hex and decimal); product, manufacturer, serial strings; interface number; class, subclass, protocol; endpoint addresses and max packet sizes; HID, raw USB, or both.

## 2. OJD Device Listing

1. From the repository root:

   ```bash
   swift run OpenJoystickDriverHIDTool --list
   ```

2. Paste `VID:0x45e` lines or Microsoft-looking devices. If VID/PID differs, use that pair below.

## 3. HID Monitor

If `--list` shows an IOHID device, replace `0x0000` with the observed PID:

```bash
swift run OpenJoystickDriverHIDTool --monitor --vid 0x045e --pid 0x0000 --seconds 30
```

Paste every `REPORT ... bytes=...`, `VALUE ...`, `POLL ...` line. On `Monitoring 0 device(s)` or no reports, keep the output and continue to raw USB.

## 4. Raw USB Monitor

Run the controller-neutral USB facade first; it uses direct IOUSBHost when the interface is accessible. If registry evidence shows an exclusive owner, a USBDriverKit experiment needs a development configuration with a matching VID/PID personality, signed host, and installed, approved development DEXT. Do not broaden the production personality.

1. Sweep endpoints:

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --length 64 --seconds 20
   ```

2. Read the reported route. If a required DEXT service is missing, capture `just diagnose-dext`; no interface-detach fallback.
3. If the sweep finds an endpoint, repeat with it, pressing one control at a time:

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --endpoint 0x81 \
     --length 64 --seconds 30
   ```

## 5. Packets to Capture

One control per packet; return to neutral between captures. Capture neutral; stick full left, right, up, down, center; stick click press and release; X1 to X6 press and release; any mode, profile, or remap state that changes the packet.

Per capture, paste the label, `REPORT ... bytes=...` or `USB_REPORT ... bytes=...`, report ID (if any), length, interface and endpoint (raw USB), known byte or bit meaning.

## 6. OJD App Check

If OJD sees the joystick:

1. In **Controllers**, select it.
2. Click **Open Input Test** (live input) or **Capture Packets...**.
3. For each action, paste recent RX entries; say whether on-screen state changed.

If only macOS tools see it, say so: it needs a DriverKit or raw USB path, not just a record.

## Minimum Parser Evidence

A parser needs: exact VID/PID; neutral packet; an independent packet per button; stick X/Y min, max, center packets; report length; report ID behavior (if any); interface and endpoint for raw USB.

## Paste-Back Report Form

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
- DEXT identity/version and activation state:

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
