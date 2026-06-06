# Steam Controller Test Notes

We have experimental Steam Controller support based on Linux `hid-steam.c`.
We still need real macOS output before calling it verified.

Test what you have:

- wired Steam Controller: `0x28de:0x1102`
- wireless receiver: `0x28de:0x1142`

Keep Steam fully quit for the first pass. If you later repeat with Steam open,
say so in the notes.

## What To Send Back

Send the easiest evidence first. Raw packets help, but even a native macOS
listing is useful if OJD cannot see the controller yet.

Please include:

- macOS version
- OJD version or commit
- whether Steam was running
- wired, wireless receiver, or both
- exact commands you ran
- full output for commands that found no device or no packets
- any terminal text caused by the controller, such as escape sequences

## 1. macOS Native Checks

Plug in the wired controller or receiver. Run these before any OJD command:

```bash
system_profiler SPUSBDataType
ioreg -p IOUSB -l -w0
ioreg -r -c IOHIDDevice -l -w0
```

Paste the entries that mention Valve, Steam, gamepad, keyboard, mouse, or
`28de`. If nothing obvious appears, unplug the controller, run the command
again, and paste the entries that disappeared.

For wired controller testing, also click in a plain Terminal window and press a
few Steam Controller buttons or the d-pad. If the terminal prints escape
sequences such as `^[[A`, paste them. That shows the controller is alive and
still in lizard keyboard mode even if OJD cannot open it yet.

## 2. OJD Device Listing

From the repository root:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --list
```

Paste every `VID:0x28de` line. If there is no `VID:0x28de` line, say that and
paste any nearby keyboard, mouse, or game controller lines that appear only while
the controller is plugged in.

## 3. Wired Controller Capture

Run the HID monitor for the expected wired PID:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
```

If it prints `Monitoring 0 device(s)`, keep that output. Then try raw USB:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --interface 0 --length 64 --seconds 20
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --interface 1 --length 64 --seconds 20
```

If either command reports access denied or busy, run the same command again with
`--detach` at the end and paste both outputs.

If you get `REPORT` or `USB_REPORT` lines, collect one neutral packet and one
packet for each action:

- A, B, X, Y press and release
- left bumper, right bumper press and release
- left grip, right grip press and release
- Back, Steam, Start press and release
- d-pad up, down, left, right press and release
- left stick full left, right, up, down, then center
- left stick click press and release
- left trigger idle, half if possible, full
- right trigger idle, half if possible, full
- left pad touch, click, and release if visible
- right pad touch, click, and release if visible

One action per capture is enough. Return to neutral between captures.

## 4. Wireless Receiver Capture

Plug in only the receiver. Keep the controller off at first.

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --list
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

During the 60 second monitor run:

1. Leave the controller off for a few seconds.
2. Turn it on and wait for connection.
3. Press and release A once.
4. Turn the controller off or disconnect it.
5. Wait 10 seconds.
6. Turn it back on without restarting the monitor.

Paste all `REPORT ... bytes=...` lines around connect and disconnect. We are
looking for these source-backed cases:

- lifecycle report `0x03` with connected payload `0x02`
- lifecycle report `0x03` with disconnected payload `0x01`
- status fallback report `0x04` when the controller was already connected

Also say whether OJD Input Test creates a usable controller only after connect,
neutralizes or removes it after disconnect, and resumes after reconnect.

## 5. Lizard Mode

Linux turns off the Steam Controller's mouse/keyboard lizard mappings while the
driver owns the controller, then restores them on close. OJD sends the same
feature report sequence. We need hardware confirmation on macOS.

Check these states:

- before OJD opens it, does the controller type keys or move the cursor?
- while OJD Input Test is receiving input, does lizard keyboard/mouse behavior stop?
- after OJD quits or the controller disconnects, does lizard behavior return?
- if you repeat with Steam open, does Steam fight OJD or duplicate input?

## Paste-Back Template

```text
OJD version/commit:
macOS version:
Steam running: yes/no
Path tested: wired / wireless / both

macOS native:
- system_profiler sees device: yes/no, entry:
- ioreg IOUSB sees device: yes/no, entry:
- ioreg IOHIDDevice sees device: yes/no, entry:
- Terminal receives lizard keyboard input: yes/no, excerpt:

OJD listing:
- OpenJoystickDriverHIDTool --list shows VID:0x28de: yes/no, lines:

Wired 0x28de:0x1102:
- HID monitor device count:
- HID REPORT lines captured: yes/no
- Raw USB reports captured: yes/no, interface/endpoint:
- Input Test buttons/sticks/triggers correct: yes/no/unknown, notes:

Wireless 0x28de:0x1142:
- HID monitor device count:
- Connect report observed: yes/no, bytes:
- Disconnect report observed: yes/no, bytes:
- Status fallback observed: yes/no, bytes:
- Input gated until connect: yes/no/unknown
- Output neutralized/removed after disconnect: yes/no/unknown
- Reconnect works without restarting OJD: yes/no/unknown

Lizard mode:
- disabled while OJD owns controller: yes/no/unknown
- restored after OJD closes: yes/no/unknown

Packet excerpts:
- neutral:
- A press:
- A release:
- left stick full left:
- left trigger full:
- receiver connect:
- receiver disconnect:

Unexpected behavior:
```
