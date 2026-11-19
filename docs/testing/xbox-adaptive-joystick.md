# Capture Xbox Adaptive Joystick Packets

Before OJD can add a record for the Xbox Adaptive Joystick, it needs to know the joystick's USB ID and what its messages (packets) look like when it's plugged straight into a Mac.

Microsoft says it works with a PC over USB-C and has 7 buttons. Microsoft doesn't publish its VID/PID, interface, endpoint, or report bytes. A public Reddit comment mentions `USB\VID_045E&PID_0B1A\...`. OJD adds no record until a tester sends output.

## What to Send Back

Fill in the [form](#paste-back-report-form). Paste the full output of commands that fail or find no device or packets too. That output shows whether HID, raw USB, or DriverKit is the next thing to try.

## 1. macOS Native Checks

1. Plug the joystick straight into the Mac, with no hub, and run:

   ```bash
   system_profiler SPUSBDataType
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOHIDDevice -l -w0
   ```

2. Paste the entries that mention Xbox, Microsoft, Adaptive, joystick, gamepad, or `045e`. If there are none, unplug it, run the commands again, and paste the entries that disappeared.
3. Write down whatever you can see:
   - vendor and product ID (hex and decimal)
   - product, manufacturer, and serial strings
   - interface number
   - class, subclass, and protocol
   - endpoint addresses and largest packet sizes
   - whether it shows up as HID, raw USB, or both

## 2. OJD Device Listing

1. From the repository root:

   ```bash
   swift run OpenJoystickDriverHIDTool --list
   ```

2. Paste the `VID:0x45e` lines, or any device that looks like it's from Microsoft. If the VID/PID is different, use that pair in the steps below.

## 3. HID Monitor

If `--list` shows an IOHID device, replace `0x0000` with the PID you saw:

```bash
swift run OpenJoystickDriverHIDTool --monitor --vid 0x045e --pid 0x0000 --seconds 30
```

Paste every `REPORT ... bytes=...`, `VALUE ...`, and `POLL ...` line. If it says `Monitoring 0 device(s)` or shows no reports, keep the output and go on to raw USB.

## 4. Raw USB Monitor

Run OJD's general USB tool first. It reads the device directly through IOUSBHost when macOS lets it. If the registry shows another program holds the device for itself, a USBDriverKit test needs a development setup: a matching VID/PID personality, a signed host app, and an installed, approved development DEXT. Don't widen the production personality.

1. Try every endpoint:

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --length 64 --seconds 20
   ```

2. Read which road it reports. If a DEXT service it needs is missing, capture `just diagnose-dext`. Don't detach the interface to get around it.
3. If the sweep finds an endpoint, run it again on that endpoint while you press one control at a time:

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000 --endpoint 0x81 \
     --length 64 --seconds 30
   ```

## 5. Packets to Capture

Use one control per packet, and let go between captures. Capture:

- the joystick at rest
- the stick fully left, right, up, down, and back in the center
- the stick click, pressed and released
- X1 to X6, each pressed and released
- any mode, profile, or remap setting that changes the packet

For each capture, paste the label, the `REPORT ... bytes=...` or `USB_REPORT ... bytes=...` line, the report ID (if any), the length, the interface and endpoint (raw USB only), and any byte or bit whose meaning you know.

## 6. OJD App Check

If OJD sees the joystick:

1. In **Controllers**, select it.
2. Click **Open Input Test** (live input) or **Capture Packets...**.
3. For each action, paste the latest RX entries and say whether the screen changed.

If only macOS tools see it, say so. Then it needs a DriverKit or raw USB road, and a record alone won't do.

## Minimum Parser Evidence

To write a parser, OJD needs:

- the exact VID/PID
- a packet at rest
- a separate packet for each button
- stick X and Y packets at the lowest, highest, and center
- the report length
- how the report ID behaves (if there is one)
- the interface and endpoint, for raw USB

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
