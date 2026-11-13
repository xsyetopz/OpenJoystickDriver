# Flydigi Tester Checks

Each card below checks one Flydigi identity on a tester build. The files you send decide what the bundled records map, so a record stays unverified until its card comes back. The maintainer has no Flydigi pad.

## Before any card

1. Install the tester build the maintainer sends, as in [Test a tester build](tester-builds.md), and keep `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG.
2. Install the command-line tool: open the app's Settings and click Install Command-Line Tool ([Command line](../../wiki/Command-Line.md)).
3. Quit games, Steam, Flydigi Space Station and other controller tools. Space Station writes to the pad and changes what it sends.
4. Make one folder per card and run the card's commands inside it, for example `mkdir -p ~/ojd-F1 && cd ~/ojd-F1`.

Commands common to every card, with `VVVV:PPPP` the identity under test:

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list > list.txt
ojd controller show VVVV:PPPP > show.txt
ojd controller capture VVVV:PPPP --duration 20 --json > capture.jsonl
```

`capture.jsonl` records 20 seconds. Start pressing when the command starts, press one control at a time, and return it to rest before the next one.

### What to send back

For every card send `OpenJoystickDriver-TESTER-BUILD.txt`, every file the card's commands wrote, and one line that lists the controls you pressed in order. Write down anything that differs from the order on the card.

## F1 Vader 4 Pro over Bluetooth (`D7D7:0041`)

Mode: pair the pad with the Mac over Bluetooth. A Vader 3 or Vader 3 Pro that shows the same `D7D7:0041` is also welcome; say which model you have.

Run the common commands with `D7D7:0041`.

Control order during the capture:

1. C, then Z.
2. Each back button in turn. Say aloud which one it is: upper or lower, left or right.
3. The Guide button.
4. The left stick: push it to the top, right, bottom and left edges, then draw one full circle at the edge. Then the right stick the same way.

Send: `capture.jsonl`, `hid.txt`, `show.txt`, the product name from the box, and the firmware version from the Flydigi app or the pad's menu.

## F2 Vader 5S over USB (`37D7:2801`)

Mode: connect the pad with a USB cable. The commands only read.

Run the common commands with `37D7:2801`. The `usb.txt` file holds the class, subclass and protocol of every interface; `show.txt` names the mode that ran.

Control order during the capture: A, B, X, Y, LB, RB, L3, R3, View, Menu, Home, then both sticks to every edge, then LT and RT fully pressed and released slowly.

Send: `usb.txt`, `show.txt`, `list.txt`, `capture.jsonl`, and `hid.txt`.

## F3 Vader 5 Pro 2.4 GHz dongle (`37D7:2401`)

Mode: plug the dongle in and switch the pad on. The commands only read. The bundled record writes its own startup packets when the pad connects; do not send any packet by hand.

Run the common commands with `37D7:2401`. The `hid.txt` file holds the report descriptor of the HID interface.

Capture 1, control order: A, B, X, Y, LB, RB, L3, R3, View, Menu, Home, C, Z, M1, M2, M3, M4, both sticks to every edge, then LT and RT fully pressed and released slowly.

Capture 2, motion: run the capture command again into `motion.jsonl` and, without touching any control, tilt the pad one axis at a time: forward and back, left and right, then twist it flat on the table.

```shell
ojd controller capture 37D7:2401 --duration 20 --json > motion.jsonl
```

Send: `usb.txt`, `hid.txt`, `list.txt`, `show.txt`, `capture.jsonl`, `motion.jsonl`, and whether `capture.jsonl` holds 32-byte reports that start with `5A A5 EF`.

## F4 Apex 4 in DInput (`04B4:2412`)

Mode: put the pad in DInput mode (the pad's mode switch or the Flydigi app). In XInput mode it shows up as `045E:028E` with the product name "Flydigi VADER3", and this card does not apply.

Run the common commands with `04B4:2412`.

Control order during the capture:

1. A, B, X, Y.
2. LB, RB, then LT and RT both half pressed and fully pressed (the trigger stops in both positions if the pad has them).
3. L3, R3, Back, Start, Home.
4. C, Z, then each back button. Say aloud which one it is.
5. D-pad up, right, down, left.
6. Both sticks to every edge.

Send: `usb.txt`, `hid.txt`, `list.txt`, `show.txt`, `capture.jsonl`.

## F5 output on a Flydigi record

Mode: any record that sends vendor frames (`37D7:2401` after F3). Run each command for 2 seconds and write down which motor moved, or that nothing moved.

```shell
ojd controller rumble 37D7:2401 --left 128 --right 0 --duration 2
ojd controller rumble 37D7:2401 --left 0 --right 128 --duration 2
ojd controller rumble 37D7:2401 --left-trigger 128 --duration 2
```

When the tester build has a trigger force setting (the release notes of the build say so), set each named mode and say whether the trigger resistance changed.

Send: a line per command: which motor moved (left grip, right grip, left trigger, right trigger, none), and one line per trigger force mode: resistance changed, yes or no.

## F6 any Flydigi pad whose model is not listed

Mode: any connection of a Flydigi pad whose model is not in the [Supported Controllers](../../wiki/Supported-Controllers.md) table.

Run the common commands with the identity `ojd controller list` shows.

Send: `hid.txt`, `usb.txt`, `list.txt`, and the model name printed on the box, so the table names the right model.
