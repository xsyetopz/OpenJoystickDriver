# Test Steam Controller Hardware

Experimental; follows Linux `hid-steam.c` and SDL `SDL_hidapi_steam.c`. No path is verified on hardware.

| Path | IDs |
| --- | --- |
| Wired | 0x28de:0x1102; prototype IDs 0x1101 (CHELL), 0x1201 (HEADCRAB) |
| Wireless receiver | 0x28de:0x1142 |
| Bluetooth LE | 0x28de:0x1105, 0x1106, 0x1202 (HEADCRAB); from SDL only, not driven by Linux `hid-steam.c` |

Quit Steam fully for the first pass; say so if you repeat with Steam open.

OJD discovery matches GamePad top-level collections and exact HID VID/PID identities from bundled records, including keyboard or mouse lizard-mode collections.

## What to Send Back

Fill the [Paste-Back Report Form](#paste-back-report-form). Add the commands run (full output of any that found no device or packets) and any terminal text the controller caused, such as escape sequences. Native listings and raw packets help even if OJD sees nothing.

## 1. macOS Native Checks

1. Plug in the wired controller or receiver.
2. Before any OJD command, run:

   ```bash
   system_profiler SPUSBDataType
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOHIDDevice -l -w0
   ```

3. Paste entries mentioning Valve, Steam, gamepad, keyboard, mouse, or `28de`. If none, unplug, rerun, paste the entries that disappeared.
4. Wired: click in a plain Terminal window and press buttons or the d-pad.
5. Paste printed escape sequences such as `^[[A` (lizard keyboard mode is active).

## 2. OJD Device Listing

1. From the repository root:

   ```bash
   swift run OpenJoystickDriverHIDTool --list
   ```

2. Paste every `VID:0x28de` line, or say none. Paste keyboard, mouse, or game controller lines present only while connected.

## 3. Wired Controller Capture

1. Run the HID monitor:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
   ```

2. On `Monitoring 0 device(s)`, keep the output; report whether **Controllers** lists the controller.
3. Try the raw USB facade (direct IOUSBHost on an accessible interface):

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --length 64 --seconds 20
   ```

4. On exclusive ownership, keep the registry owner as evidence. A development DEXT experiment needs an exact Valve personality (these pairs are outside the production Apple USB entitlement). No silent detach or transport fallback.
5. For `REPORT` or `USB_REPORT` lines, collect one neutral packet and one per action, one at a time, returning to neutral between captures:

   | Input | Action |
   | --- | --- |
   | Buttons | Press and release: A, B, X, Y; left and right bumper; left and right grip; Back, Steam, Start; d-pad up, down, left, right; left stick click |
   | Left stick | Full left, right, up, down, then center |
   | Each trigger | Idle, half if possible, full |
   | Each pad | Touch, click, release if visible |
   | Motion | At rest face up, then roll the right edge down and hold (settles the unverified gyro and accelerometer handedness) |

## 4. Wireless Receiver Capture

Plug in only the receiver; controller off.

```bash
swift run OpenJoystickDriverHIDTool --list
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

During the 60 second run:

1. Leave the controller off a few seconds.
2. Turn it on; wait for connection.
3. Press and release A once.
4. Turn it off or disconnect it; wait 10 seconds.
5. Turn it on without restarting the monitor.

Paste all `REPORT ... bytes=...` lines around connect and disconnect. Check for:

| Event | Report |
| --- | --- |
| Connected | Lifecycle report 0x03, payload 0x02 |
| Disconnected | Lifecycle report 0x03, payload 0x01 |
| Already connected | Status fallback report 0x04 |

Report whether **Controllers** lists the controller only after connect, clears it after disconnect, lists it again after reconnect.

## 5. Per-Interface Roles

OJD runs one controller per Steam interface whose HID report descriptor has a Feature item, as `hid-steam.c` does. Per `hid-steam.c`: wired exposes mouse 0, keyboard 1, gamepad 2; dongle exposes keyboard 0, slots 1-4. Not verified on macOS.

1. For each path, run `ioreg -r -c IOHIDDevice -l -w0`. For every `28de` entry, paste the parent `IOUSBHostInterface` `bInterfaceNumber` and `ReportDescriptor` bytes. Say which descriptors contain a Feature item (prefix byte 0xB0-0xB3).
2. Start OJD and run (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `ValveSteamController` per Feature interface: wired `interfaceNumber` 2; dongle up to four entries, interfaces 1 to 4. `ojd controller show <ID> --json` gives each `interfaceNumber`. Paste the output and any interfaces `ojd status` lists as unbound.
3. Dongle: pair controllers one at a time; record which interface's entry receives input. Power one off; only its entry reports disconnected.

## 6. Bluetooth LE

State arrives as 20-byte report 0x03 segments, joined into one packet as SDL `SteamControllerPacketAssembler` does. A packet carries only changed chunks; OJD keeps the last value of the rest. Settings also travel as report 0x03 segments. Startup selects wireless packet version 2, as SDL `ResetSteamController` does.

1. Pair the controller in System Settings > Bluetooth; hold Steam and Y while turning it on to start Bluetooth mode.
2. Run `ioreg -r -c IOHIDDevice -l -w0`; paste the `28de` entry with `Transport` and `ReportDescriptor`.
3. Monitor the PID from `ioreg`:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1106 --seconds 30
   ```

4. Capture the section 3 actions; paste the `REPORT` lines. Say whether an action gives one report or several short ones.
5. Start OJD. In **Controllers**, select the controller and click **Open Input Test**. Check it shows as Bluetooth LE and all inputs move.
6. Hold one button and move one stick; the button stays pressed while only the stick changes.

## 7. Lizard Mode

Linux disables the mouse and keyboard lizard mappings while the driver owns the controller, restoring them on close. OJD sends the same feature-report sequence.

| When | Expect or record |
| --- | --- |
| Before OJD opens it | Record whether it types keys or moves the cursor |
| While Input Test receives input | Lizard behavior stops |
| After OJD quits or the controller disconnects | Lizard behavior returns |
| With Steam open | Record conflicts with OJD or duplicate input |

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
- Input Test buttons/sticks/triggers correct: yes/no/unknown, notes:

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
- Input Test input correct: yes/no/unknown, notes:
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
