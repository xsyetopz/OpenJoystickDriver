# 8BitDo Tester Checks

Each card below checks one 8BitDo identity on a tester build. The files you send decide what the bundled record maps, so a record stays unverified until its card comes back.

## Before Any Card

1. Install the tester build the maintainer sends, as in [Test a tester build](tester-builds.md), and keep `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG.
2. Install the command-line tool: open the app's Settings and click Install Command-Line Tool ([Command line](../../wiki/Command-Line.md)).
3. Quit games, Steam and other controller tools.
4. Make one folder per card and run the card's commands inside it, for example `mkdir -p ~/ojd-T1 && cd ~/ojd-T1`.

`capture.jsonl` records 20 seconds. Start pressing when the command starts, press one control at a time, and return it to rest before the next one.

### Control Order

Press the controls in this order during a capture, and skip a control the pad lacks:

1. A, B, X, Y.
2. LB, RB.
3. L3, R3 (stick clicks).
4. View, Menu, Home, Capture.
5. Each rear button: left side before right side, upper before lower.
6. Left stick up, right, down, left; then the right stick the same way.
7. D-pad up, right, down, left.
8. LT, then RT, each pressed fully and released slowly.

### What to Send Back

For every card send `OpenJoystickDriver-TESTER-BUILD.txt`, every file the card's commands wrote, and one line that lists the controls you pressed in order. Write down anything that differs from the order above.

## T1 Ultimate 2C Over Bluetooth LE (`2DC8:301B`)

Mode: pair the Ultimate 2C with the Mac over Bluetooth.

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list > list.txt
ojd controller show 2DC8:301B > show.txt
ojd controller capture 2DC8:301B --duration 20 --json > capture.jsonl
```

Control order: the right stick up, right, down, left first, then LT and RT, then the full [control order](#control-order) including L4 and R4.

Send: the common files, and which right-stick directions moved a value in `ojd` and which moved a trigger.

## T2 Ultimate 2C Receiver (`2DC8:301C`)

Mode: plug the receiver in with the pad switched off. Run the first line at once; it reads the bus at 0, 3, 8 and 15 seconds.

```shell
ioreg -p IOUSB -l -w0 > usb-0s.txt; sleep 3; ioreg -p IOUSB -l -w0 > usb-3s.txt; sleep 5; ioreg -p IOUSB -l -w0 > usb-8s.txt; sleep 7; ioreg -p IOUSB -l -w0 > usb-15s.txt
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ojd controller list > list.txt
```

Then switch the pad on and run these with the PID `ojd controller list` shows for 8BitDo (`301C` or `310A`):

```shell
ojd controller show 2DC8:PPPP > show.txt
ojd controller capture 2DC8:PPPP --duration 20 --json > capture.jsonl
```

Control order: the full [control order](#control-order).

Send: all files, and whether the PID changed from `301C` to `310A`.

## T3 Ultimate 2C Adapter (`2DC8:3109`)

Mode: the adapter in standby (pad off), then with the pad on. These commands only read; do not change settings in 8BitDo software during the check.

With the pad off:

```shell
ioreg -r -c IOHIDDevice -l -w0 > standby-hid.txt
ioreg -p IOUSB -l -w0 > standby-usb.txt
ojd controller list > standby-list.txt
ojd controller show 2DC8:3109 > standby-show.txt
```

With the pad on:

```shell
ioreg -r -c IOHIDDevice -l -w0 > on-hid.txt
ioreg -p IOUSB -l -w0 > on-usb.txt
ojd controller list > on-list.txt
ojd controller show 2DC8:3109 > on-show.txt
ojd controller capture 2DC8:3109 --duration 20 --json > on-capture.jsonl
```

Control order: the full [control order](#control-order) during `on-capture.jsonl`.

Send: both sets of files.

## T4 Ultimate 2C Wired in DInput (`2DC8:301D`)

Mode: hold B while you switch the pad on, then connect the cable.

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list > list.txt
ojd controller show 2DC8:301D > show.txt
ojd controller capture 2DC8:301D --duration 20 --json > capture.jsonl
```

Control order: the full [control order](#control-order), with each rear button.

Send: the common files, and the position of each rear button you pressed.

## T5 Ultimate 2 Over Cable and Dongle (`2DC8:6012`)

Mode: connect the Ultimate 2 by cable and run the first block; then unplug the cable, connect the dongle and run the second block.

```shell
ioreg -r -c IOHIDDevice -l -w0 > cable-hid.txt
ioreg -p IOUSB -l -w0 > cable-usb.txt
ojd controller list > cable-list.txt
ojd controller show 2DC8:6012 > cable-show.txt
ojd controller capture 2DC8:6012 --duration 20 --json > cable-capture.jsonl
```

```shell
ioreg -r -c IOHIDDevice -l -w0 > dongle-hid.txt
ioreg -p IOUSB -l -w0 > dongle-usb.txt
ojd controller list > dongle-list.txt
ojd controller show 2DC8:6012 > dongle-show.txt
ojd controller capture 2DC8:6012 --duration 20 --json > dongle-capture.jsonl
```

Control order: the full [control order](#control-order) in each capture, with the four rear buttons.

Then put the pad in DInput mode and run a motion capture; repeat in Switch mode with `switch-motion.jsonl`. During each, hold the pad still for 3 seconds, then tilt it forward and back, roll it left and right, and turn it left and right.

```shell
ojd controller capture 2DC8:6012 --duration 20 --json > dinput-motion.jsonl
```

Send: all files, and the button each rear button acts as on the pad (for example "upper left rear acts as L3").

## T6 Ultimate 2 Receiver and Dongle (`2DC8:6013`, `2DC8:3107`)

Mode: plug in the receiver with the pad off, run the block, switch the pad on and run it again with `on-` in place of `off-`. Repeat both runs with the dongle and `3107` in place of `6013`.

```shell
ioreg -r -c IOHIDDevice -l -w0 > 6013-off-hid.txt
ioreg -p IOUSB -l -w0 > 6013-off-usb.txt
ojd controller list > 6013-off-list.txt
ojd controller show 2DC8:6013 > 6013-off-show.txt
ojd controller capture 2DC8:6013 --duration 20 --json > 6013-off-capture.jsonl
```

Control order: the full [control order](#control-order) during each `on-` capture.

Send: all files, and the PID `ojd controller list` showed in each run.

## T7 Ultimate 2 and Pro 3 on `2DC8:310B`

Mode: connect the Ultimate 2 in the mode that shows `310B`; then, if you own one, the Pro 3 the same way.

```shell
ioreg -r -c IOHIDDevice -l -w0 > ultimate2-hid.txt
ioreg -p IOUSB -l -w0 > ultimate2-usb.txt
```

For the Pro 3, run the same lines with `pro3-` in place of `ultimate2-`.

Control order: none; the product strings and `bcdDevice` in these files decide the mode.

Send: all files, and the mode switch position of each pad.

## T8 Ultimate 3-mode Over Bluetooth in Xbox Mode (`2DC8:901B`)

Mode: set the pad to Xbox mode and pair it with the Mac over Bluetooth.

```shell
ioreg -r -c IOHIDDevice -l -w0 > hid.txt
ioreg -p IOUSB -l -w0 > usb.txt
ojd controller list > list.txt
ojd controller show 2DC8:901B > show.txt
ojd controller capture 2DC8:901B --duration 20 --json > capture.jsonl
```

Control order: the full [control order](#control-order).

Send: the common files.

## T9 Watchdog with `2DC8:310A` and `2DC8:6012` Served

Mode: connect the Ultimate 2C dongle (`310A`) and confirm with `ojd controller show 2DC8:310A` that OJD serves it. Touch no control during the check. Each line saves the time and the bus.

```shell
{ date; ioreg -p IOUSB -l -w0; } > 310A-0min.txt
sleep 300; { date; ioreg -p IOUSB -l -w0; } > 310A-5min.txt
ojd controller suspend 2DC8:310A > 310A-suspend.txt
sleep 10; { date; ioreg -p IOUSB -l -w0; } > 310A-suspended-10s.txt
sleep 50; { date; ioreg -p IOUSB -l -w0; } > 310A-suspended-60s.txt
ojd controller resume 2DC8:310A > 310A-resume.txt
ojd controller list > 310A-list-after.txt
```

Repeat the block with the Ultimate 2 (`6012`), with `6012` in place of `310A`.

Control order: none.

Send: all files, and for each pad whether it worked again after `resume` without reconnecting it.
