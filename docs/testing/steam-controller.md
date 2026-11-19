# Test Steam Controller Hardware

Support for the original Steam Controller is experimental. It follows Linux's `hid-steam.c` and SDL's `SDL_hidapi_steam.c`. Nobody has confirmed any kind of connection on hardware yet.

| Path | IDs |
| --- | --- |
| Wired | 0x28de:0x1102; prototype IDs 0x1101 (CHELL), 0x1201 (HEADCRAB) |
| Wireless receiver | 0x28de:0x1142 |
| Bluetooth LE | 0x28de:0x1105, 0x1106, 0x1202 (HEADCRAB); from SDL only; Linux `hid-steam.c` doesn't drive these |

Quit Steam completely for the first run. If you run it again with Steam open, say so.

On its own, the controller pretends to be a keyboard and mouse. People call that lizard mode. OJD finds HID devices that say they're a gamepad, plus exact VID/PID matches from its bundled records, including the keyboard and mouse parts of lizard mode.

## What to Send Back

Fill in the [Paste-Back Report Form](#paste-back-report-form). Add the commands you ran (with the full output of any that found no device or packets), and any text the controller typed into Terminal, such as escape sequences. macOS listings and raw packets help even if OJD sees nothing.

## 1. macOS Native Checks

1. Plug in the wired controller or receiver.
2. Before any OJD command, run:

   ```bash
   system_profiler SPUSBDataType
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOHIDDevice -l -w0
   ```

3. Paste the entries that mention Valve, Steam, gamepad, keyboard, mouse, or `28de`. If there are none, unplug it, run the commands again, and paste the entries that disappeared.
4. Wired only: click in a plain Terminal window and press buttons or the D-pad.
5. Paste any escape sequences it types, such as `^[[A`. Those mean lizard keyboard mode is on.

## 2. OJD Device Listing

1. From the repository root:

   ```bash
   swift run OpenJoystickDriverHIDTool --list
   ```

2. Paste every `VID:0x28de` line, or say there are none. Also paste keyboard, mouse, or game controller lines that only show up while it's plugged in.

## 3. Wired Controller Capture

1. Run the HID monitor:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
   ```

2. If it says `Monitoring 0 device(s)`, keep the output and report whether **Controllers** lists the controller.
3. Try OJD's raw USB tool, which reads the interface directly through IOUSBHost when macOS allows it:

   ```bash
   swift run OpenJoystickDriverHIDTool --usb-monitor --vid 0x28de --pid 0x1102 --length 64 --seconds 20
   ```

4. If another program holds the device for itself, write down which one the registry shows. A development DEXT test needs an exact Valve personality, because these IDs aren't in Apple's production USB entitlement. OJD never quietly detaches the device or switches to another kind of connection.
5. If you get `REPORT` or `USB_REPORT` lines, collect one packet at rest and one for each action below. Do one action at a time and let go between captures:

   | Input | Action |
   | --- | --- |
   | Buttons | Press and release: A, B, X, Y; left and right bumper; left and right grip; Back, Steam, Start; d-pad up, down, left, right; left stick click |
   | Left stick | Full left, right, up, down, then center |
   | Each trigger | Idle, half if possible, full |
   | Each pad | Touch, click, release if visible |
   | Motion | At rest face up, then tip the right edge down and hold (this shows which way the gyro and accelerometer count, which nobody has checked) |

## 4. Wireless Receiver Capture

Plug in only the receiver, with the controller off.

```bash
swift run OpenJoystickDriverHIDTool --list
swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

During the 60 second run:

1. Leave the controller off for a few seconds.
2. Turn it on and wait for it to connect.
3. Press and release A once.
4. Turn it off or disconnect it, and wait 10 seconds.
5. Turn it on again without restarting the monitor.

Paste all `REPORT ... bytes=...` lines around connecting and disconnecting. Look for:

| Event | Report |
| --- | --- |
| Connected | Lifecycle report 0x03, payload 0x02 |
| Disconnected | Lifecycle report 0x03, payload 0x01 |
| Already connected | Status fallback report 0x04 |

Report whether **Controllers** lists the controller only once it connects, drops it when it disconnects, and lists it again when it reconnects.

## 5. Which Interface Is the Controller

A USB device can show up as several parts, called interfaces. OJD runs one controller for each Steam interface whose HID report descriptor has a Feature item, as `hid-steam.c` does. According to `hid-steam.c`, wired shows mouse 0, keyboard 1, and gamepad 2. The dongle shows keyboard 0 and controller slots 1 to 4. Nobody has checked this on macOS.

1. For each path, run `ioreg -r -c IOHIDDevice -l -w0`. For every `28de` entry, paste the parent `IOUSBHostInterface` `bInterfaceNumber` and `ReportDescriptor` bytes. Say which descriptors contain a Feature item (prefix byte 0xB0 to 0xB3).
2. Start OJD and run (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `ValveSteamController` for each Feature interface: `interfaceNumber` 2 when wired, and up to four entries on interfaces 1 to 4 for the dongle. `ojd controller show <ID> --json` gives each `interfaceNumber`. Paste the output and any interfaces that `ojd status` lists as unbound.
3. Dongle only: pair controllers one at a time, and write down which interface's entry gets input. Turn one off. Only its entry should report disconnected.

## 6. Bluetooth LE

Over Bluetooth LE, the controller's state comes in small pieces: 20-byte report 0x03 segments. OJD glues them into one packet the way SDL's `SteamControllerPacketAssembler` does. A packet only carries the pieces that changed, so OJD keeps the last value of the rest. Settings travel as report 0x03 segments too. At startup OJD picks wireless packet version 2, as SDL's `ResetSteamController` does.

1. Pair the controller in System Settings > Bluetooth. To start Bluetooth mode, hold Steam and Y while you turn it on.
2. Run `ioreg -r -c IOHIDDevice -l -w0`, and paste the `28de` entry with `Transport` and `ReportDescriptor`.
3. Monitor the PID from `ioreg`:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1106 --seconds 30
   ```

4. Capture the actions from section 3 and paste the `REPORT` lines. Say whether an action gives one report or several short ones.
5. Start OJD. In **Controllers**, select the controller and click **Open Input Test**. Check that it shows as Bluetooth LE and all inputs move.
6. Hold one button and move one stick. The button should stay pressed while only the stick changes.

## 7. Lizard Mode

Linux turns off the lizard mouse and keyboard while its driver holds the controller, and turns them back on when it lets go. OJD sends the same feature reports.

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
