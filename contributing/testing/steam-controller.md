# Test Steam Controller Hardware

Experimental Steam Controller support is based on Linux `hid-steam.c` and SDL `SDL_hidapi_steam.c`. Verification requires real macOS output.

Supported test paths:

- wired Steam Controller: `0x28de:0x1102`, and the prototype IDs `0x1101` (CHELL) and `0x1201` (HEADCRAB)
- wireless receiver: `0x28de:0x1142`
- Bluetooth LE: `0x28de:0x1105` and `0x1106`, and `0x1202` (HEADCRAB)

The Bluetooth LE path comes from SDL only. Linux `hid-steam.c` does not drive it. None of the paths is hardware-verified.

Keep Steam fully quit for the first pass. If you later repeat with Steam open, say so in the notes.

OJD production discovery now matches both normal GamePad top-level collections and exact HID VID/PID identities loaded from bundled records. This specifically covers Steam Controller collections that remain exposed as keyboard or mouse lizard-mode devices.

## What To Send Back

Start with the easiest evidence: native macOS listings and raw packets help even if OJD cannot see the controller.

Include:

- macOS version
- OJD version or commit
- whether Steam was running
- wired, wireless receiver, or both
- exact commands you ran
- full output for commands that found no device or no packets
- any terminal text caused by the controller, such as escape sequences

## 1. macOS Native Checks

Plug in the wired controller or receiver, then run these before any OJD command:

```bash
system_profiler SPUSBDataType
ioreg -p IOUSB -l -w0
ioreg -r -c IOHIDDevice -l -w0
```

Paste the entries that mention Valve, Steam, gamepad, keyboard, mouse, or `28de`. If nothing obvious appears, unplug the controller and run the commands again. Paste the entries that disappeared.

For wired testing, click in a plain Terminal window and press a few Steam Controller buttons or the d-pad. Paste any escape sequences the terminal prints, such as `^[[A`. This shows that the controller is alive and still in lizard keyboard mode, even if OJD cannot open it yet.

## 2. OJD Device Listing

From the repository root:

```bash
swift run OpenJoystickDriverHIDTool --list
```

Paste every `VID:0x28de` line. If none appear, say so and paste nearby keyboard, mouse, or game controller lines present only while connected.

## 3. Wired Controller Capture

Run the HID monitor for the expected wired PID:

```bash
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
```

If it still prints `Monitoring 0 device(s)`, keep that output and also report whether Controller Settings lists the controller. Try the controller-neutral raw USB facade next; an accessible interface uses direct IOUSBHost:

```bash
swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --length 64 --seconds 20
```

If direct open reports exclusive ownership, preserve the registry owner as evidence. A development DEXT experiment then requires an exact Valve personality; these pairs are not in the current production Apple USB entitlement. Do not add a silent detach or transport fallback.

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
- motion: at rest face up, then roll the right edge down and hold; this settles the unverified gyro and accelerometer handedness

One action per capture is enough. Return to neutral between captures.

## 4. Wireless Receiver Capture

Plug in only the receiver. Keep the controller off at first.

```bash
swift run OpenJoystickDriverHIDTool --list
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

During the 60 second monitor run:

1. Leave the controller off for a few seconds.
1. Turn it on and wait for connection.
1. Press and release A once.
1. Turn the controller off or disconnect it.
1. Wait 10 seconds.
1. Turn it back on without restarting the monitor.

Paste all `REPORT ... bytes=...` lines around connect and disconnect. Check these source-backed cases:

- lifecycle report `0x03` with connected payload `0x02`
- lifecycle report `0x03` with disconnected payload `0x01`
- status fallback report `0x04` when the controller was already connected

Also say whether Controller Settings lists the controller only after connect, clears it after disconnect, and resumes after reconnect.

## 5. Per-Interface Roles

OJD runs one controller per Steam interface whose HID report descriptor has a Feature item, as Linux `hid-steam.c` does; other interfaces are not controllers. Per `hid-steam.c`, the wired controller exposes mouse 0, keyboard 1 and gamepad 2, and the dongle exposes keyboard 0 and slots 1–4. None of this has been verified on macOS hardware yet.

1. For each path, run `ioreg -r -c IOHIDDevice -l -w0` and paste, for every `28de` entry, the parent `IOUSBHostInterface` `bInterfaceNumber` and the `ReportDescriptor` bytes. Say which descriptors contain a Feature item (item prefix byte `0xB0`–`0xB3`).
1. Start OJD and run (`ojd` is the [command-line tool](../../docs/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `valve.steam-controller` per Feature interface: wired `interfaceNumber` 2; dongle up to four entries for interfaces 1 to 4. `ojd controller show <ID> --json` gives each entry's `interfaceNumber`. Paste the output and any interfaces that `ojd status` lists as unbound.
1. Dongle only: pair controllers one at a time and record which interface's entry receives input. Power one off and confirm only its entry reports disconnected.

## 6. Bluetooth LE

Over Bluetooth LE the controller sends its state as 20-byte report `0x03` segments. OJD joins the segments into one packet, as SDL `SteamControllerPacketAssembler` does. A packet carries only the chunks that changed, and OJD keeps the last value of every chunk that is not in the packet. Settings travel as report `0x03` segments too. Startup also selects wireless packet version 2, as SDL `ResetSteamController` does.

1. Pair the controller in System Settings > Bluetooth. Hold Steam and Y while you turn it on to start Bluetooth mode.
1. Run `ioreg -r -c IOHIDDevice -l -w0` and paste the `28de` entry with its `Transport` and `ReportDescriptor`.
1. Run the HID monitor with the PID that `ioreg` shows:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1106 --seconds 30
   ```

1. Capture the same actions as in section 3. Paste the `REPORT` lines. Say whether one action gives one report or several short reports.
1. Start OJD and check that Controller Settings Live shows the controller as Bluetooth LE and that buttons, sticks, triggers and trackpads move.
1. Hold one button and move one stick. Check that the held button stays pressed while only the stick changes.

## 7. Lizard Mode

Linux turns off the Steam Controller's mouse/keyboard lizard mappings while the driver owns the controller, then restores them on close. OJD sends the same feature-report sequence; confirm its effect on macOS hardware.

Check these states:

- Before OJD opens it: record whether the controller types keys or moves the cursor.
- While Controller Settings Live receives input: check that lizard keyboard/mouse behavior stops.
- After OJD quits or the controller disconnects: check that lizard behavior returns.
- If repeating with Steam open: record conflicts with OJD or duplicate input.

## Paste-Back Report Form

```text
OJD version/commit:
macOS version:
Steam running: yes/no
Path tested: wired / wireless / Bluetooth LE (PID:)

Per-interface roles:
- Feature interfaces (bInterfaceNumber):
- `ojd controller show --json` `interfaceNumber` values:

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

Bluetooth LE:
- ioreg Transport:
- REPORT lines are 20-byte report 0x03 segments: yes/no
- Controller Settings Live input correct: yes/no/unknown, notes:
- held button survives a stick-only change: yes/no/unknown

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
