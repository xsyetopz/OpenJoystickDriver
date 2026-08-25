# Test Steam Controller hardware

We have experimental Steam Controller support based on Linux `hid-steam.c`. We still need real macOS output before calling it verified.

You can test:

- wired Steam Controller: `0x28de:0x1102`
- wireless receiver: `0x28de:0x1142`

Keep Steam fully quit for the first pass. If you later repeat with Steam open, say so in the notes.

OJD production discovery now matches both normal GamePad top-level collections and exact HID VID/PID identities loaded from bundled records. This specifically covers Steam Controller collections that remain exposed as keyboard or mouse lizard-mode devices.

## What to send back

Start with the easiest evidence. If OJD cannot see the controller, a native macOS listing is still useful. Raw packets also help.

Include:

- macOS version
- OJD version or commit
- whether Steam was running
- wired, wireless receiver, or both
- exact commands you ran
- full output for commands that found no device or no packets
- any terminal text caused by the controller, such as escape sequences

## 1. macOS native checks

Plug in the wired controller or receiver, then run these before any OJD command:

```bash
system_profiler SPUSBDataType
ioreg -p IOUSB -l -w0
ioreg -r -c IOHIDDevice -l -w0
```

Paste the entries that mention Valve, Steam, gamepad, keyboard, mouse, or `28de`. If nothing obvious appears, unplug the controller and run the commands again. Paste the entries that disappeared.

For wired testing, click in a plain Terminal window and press a few Steam Controller buttons or the d-pad. Paste any escape sequences the terminal prints, such as `^[[A`. This shows that the controller is alive and still in lizard keyboard mode, even if OJD cannot open it yet.

## 2. OJD device listing

From the repository root:

```bash
swift run OpenJoystickDriverHIDTool --list
```

Paste every `VID:0x28de` line. If there is no `VID:0x28de` line, say that and paste any nearby keyboard, mouse, or game controller lines that appear only while the controller is plugged in.

## 3. Wired controller capture

Run the HID monitor for the expected wired PID:

```bash
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
```

If it still prints `Monitoring 0 device(s)`, keep that output and also report
whether Controller Settings lists the controller. Try the controller-neutral raw
USB facade next; an accessible interface uses direct IOUSBHost:

```bash
swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --length 64 --seconds 20
```

If direct open reports exclusive ownership, preserve the registry owner as
evidence. A development DEXT experiment then requires an exact Valve personality;
these pairs are not in the current production Apple USB entitlement. Do not add a
silent detach or transport fallback.

If you get `REPORT` or `USB_REPORT` lines, collect one neutral packet and one packet for each action:

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

## 4. Wireless receiver capture

Plug in only the receiver. Keep the controller off at first.

```bash
swift run OpenJoystickDriverHIDTool --list
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

During the 60 second monitor run:

1. Leave the controller off for a few seconds.
2. Turn it on and wait for connection.
3. Press and release A once.
4. Turn the controller off or disconnect it.
5. Wait 10 seconds.
6. Turn it back on without restarting the monitor.

Paste all `REPORT ... bytes=...` lines around connect and disconnect. We are looking for these source-backed cases:

- lifecycle report `0x03` with connected payload `0x02`
- lifecycle report `0x03` with disconnected payload `0x01`
- status fallback report `0x04` when the controller was already connected

Also say whether Controller Settings lists the controller only after connect, clears it after disconnect, and resumes after reconnect.

## 5. Lizard Mode

Linux turns off the Steam Controller's mouse/keyboard lizard mappings while the driver owns the controller, then restores them on close. OJD sends the same feature report sequence. We need hardware confirmation on macOS.

Check these states:

- before OJD opens it, does the controller type keys or move the cursor?
- while OJD Controller Settings Live is receiving input, does lizard keyboard/mouse behavior stop?
- after OJD quits or the controller disconnects, does lizard behavior return?
- if you repeat with Steam open, does Steam fight OJD or duplicate input?

## Paste-Back Report Form

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
- Controller Settings Live buttons/sticks/triggers correct: yes/no/unknown, notes:

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
