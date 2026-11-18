# Flydigi Tester Checks

Each card checks one identity. A record stays unverified until its card returns. The maintainer has no Flydigi pad.

## Before Any Card

1. Install the tester build ([Test a Tester Build](tester-builds.md)). Keep `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG.
2. In Settings, click **Install Command-Line Tool** ([Command Line](../../wiki/Command-Line.md)).
3. Quit games, Steam, Flydigi Space Station, and other controller tools. Space Station writes to the pad and changes its output.
4. Use one folder per card, for example `mkdir -p ~/ojd-F1 && cd ~/ojd-F1`.

Run these in every card, with the heading's VID:PID as `VVVV:PPPP`:

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list > list.txt
ojd controller show VVVV:PPPP > show.txt
ojd controller capture VVVV:PPPP --duration 20 --json > capture.jsonl
```

`capture.jsonl` records 20 seconds. Press when it starts, one control at a time, returning each to rest.

### What to Send Back

- `OpenJoystickDriver-TESTER-BUILD.txt`
- Every file written, unless the card names fewer
- One line of controls pressed, in order, noting differences from the card

## F1 Vader 4 Pro over Bluetooth (D7D7:0041)

A Vader 3 or Vader 3 Pro with this ID also works. Say which.

1. Pair the pad over Bluetooth.
2. Run the common commands.
3. During the capture, press C, Z, each back button (note upper or lower, left or right), Guide, then each stick at top, right, bottom, left edges and one full circle.
4. Send `capture.jsonl`, `hid.txt`, `show.txt`, the box product name, and the firmware version from the Flydigi app or pad menu.

## F2 Vader 5S over USB (37D7:2801)

Read-only. `usb.txt` holds each interface's class, subclass, and protocol; `show.txt` names the mode that ran.

1. Connect the pad by USB cable.
2. Run the common commands.
3. During the capture, press A, B, X, Y, LB, RB, L3, R3, View, Menu, Home. Push both sticks to every edge. Press LT and RT fully, release slowly.

## F3 Vader 5 Pro 2.4 GHz Dongle (37D7:2401)

Read-only. The bundled record writes its own startup packets on connect; send none by hand. `hid.txt` holds the HID report descriptor.

1. Plug in the dongle and switch the pad on.
2. Run the common commands.
3. During capture 1, press A, B, X, Y, LB, RB, L3, R3, View, Menu, Home, C, Z, M1 to M4. Push both sticks to every edge. Press LT and RT fully, release slowly.
4. Capture 2 (motion), touching no control:

   ```shell
   ojd controller capture 37D7:2401 --duration 20 --json > motion.jsonl
   ```

5. Tilt the pad forward and back, left and right, then twist it flat on the table.
6. Also send `motion.jsonl`. Say if `capture.jsonl` has 32-byte reports starting `5A A5 EF`.

## F4 Apex 4 in DInput (04B4:2412)

Not for XInput mode (045E:028E, "Flydigi VADER3").

1. Set DInput mode with the mode switch or the Flydigi app.
2. Run the common commands.
3. During the capture, press A, B, X, Y, LB, RB, LT and RT half and fully (if the pad has both stops), L3, R3, Back, Start, Home, C, Z, each back button (note its position), the D-pad in four directions, and both sticks to every edge.

## F5 Output on a Flydigi Record

For any record that sends vendor frames (37D7:2401 after F3).

1. Run each for 2 seconds. Note which motor moved, or none.

   ```shell
   ojd controller rumble 37D7:2401 --left 128 --right 0 --duration 2
   ojd controller rumble 37D7:2401 --left 0 --right 128 --duration 2
   ojd controller rumble 37D7:2401 --left-trigger 128 --duration 2
   ```

2. If the release notes list a trigger force setting, set each mode and note whether resistance changed.
3. Send one line per command (left grip, right grip, left trigger, right trigger, or none) and per trigger force mode (resistance changed, yes or no).

## F6 Any Flydigi Pad Whose Model Is Not Listed

For any Flydigi pad missing from the [Supported Controllers](../../wiki/Supported-Controllers.md) table.

1. Run the common commands with the identity from `ojd controller list`.
2. Send `hid.txt`, `usb.txt`, `list.txt`, and the box model name.

## Further Reading

- [Test a Tester Build](tester-builds.md)
- [Supported Controllers](../../wiki/Supported-Controllers.md)
- [Command Line](../../wiki/Command-Line.md)
