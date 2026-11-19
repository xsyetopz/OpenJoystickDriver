# 8BitDo Tester Checks

Each card below tests one 8BitDo controller ID. A record stays unconfirmed until someone sends its card back.

## Before Any Card

1. Install the tester build ([Test a Tester Build](tester-builds.md)), and keep `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG.
2. In Settings, click **Install Command-Line Tool** ([Command Line](../../wiki/Command-Line.md)).
3. Quit games, Steam, and other controller tools.
4. Make one folder per card and run its commands inside it. For example: `mkdir -p ~/ojd-T1 && cd ~/ojd-T1`.

`capture.jsonl` records for 20 seconds. Start pressing when the command starts, one control at a time, and let each one go back to rest.

### Control Order

Skip any control your pad doesn't have.

| Step | Controls |
| --- | --- |
| 1 | A, B, X, Y |
| 2 | LB, RB |
| 3 | L3, R3 (stick clicks) |
| 4 | View, Menu, Home, Capture |
| 5 | Each rear button: left side before right side, upper before lower |
| 6 | Left stick up, right, down, left; then the right stick the same way |
| 7 | D-pad up, right, down, left |
| 8 | LT, then RT, each pressed all the way and let go slowly |

### What to Send Back

For each card: `OpenJoystickDriver-TESTER-BUILD.txt`, every file the card's commands wrote, and one line listing the controls you pressed, in order, with anything you did differently from the order above.

## T1 Ultimate 2C over Bluetooth LE (2DC8:301B)

1. Pair the Ultimate 2C over Bluetooth.
2. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > hid.txt
   ioreg -p IOUSB -l -w0 > usb.txt
   ojd controller list > list.txt
   ojd controller show 2DC8:301B > show.txt
   ojd controller capture 2DC8:301B --duration 20 --json > capture.jsonl
   ```

3. During the capture, push the right stick up, right, down, and left, then press LT and RT, then follow the [control order](#control-order) with L4 and R4.
4. Report which right stick directions moved a stick value in `ojd` and which moved a trigger.

## T2 Ultimate 2C Receiver (2DC8:301C)

1. Plug in the receiver, with the pad off.
2. Run these together (the first line reads the USB bus at 0, 3, 8, and 15 seconds):

   ```shell
   ioreg -p IOUSB -l -w0 > usb-0s.txt; sleep 3; ioreg -p IOUSB -l -w0 > usb-3s.txt; sleep 5; ioreg -p IOUSB -l -w0 > usb-8s.txt; sleep 7; ioreg -p IOUSB -l -w0 > usb-15s.txt
   ioreg -r -c IOHIDDevice -l -w0 > hid.txt
   ojd controller list > list.txt
   ```

3. Switch the pad on.
4. Run with the 8BitDo PID from `ojd controller list` (301C or 310A):

   ```shell
   ojd controller show 2DC8:PPPP > show.txt
   ojd controller capture 2DC8:PPPP --duration 20 --json > capture.jsonl
   ```

5. During the capture, follow the [control order](#control-order).
6. Report whether the PID changed from 301C to 310A.

## T3 Ultimate 2C Adapter (2DC8:3109)

These commands only read. Don't change any 8BitDo software settings.

1. With the adapter in standby (pad off), run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > standby-hid.txt
   ioreg -p IOUSB -l -w0 > standby-usb.txt
   ojd controller list > standby-list.txt
   ojd controller show 2DC8:3109 > standby-show.txt
   ```

2. Switch the pad on.
3. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > on-hid.txt
   ioreg -p IOUSB -l -w0 > on-usb.txt
   ojd controller list > on-list.txt
   ojd controller show 2DC8:3109 > on-show.txt
   ojd controller capture 2DC8:3109 --duration 20 --json > on-capture.jsonl
   ```

4. During `on-capture.jsonl`, follow the [control order](#control-order).

## T4 Ultimate 2C Wired in DInput (2DC8:301D)

1. Hold B while switching the pad on.
2. Connect the cable.
3. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > hid.txt
   ioreg -p IOUSB -l -w0 > usb.txt
   ojd controller list > list.txt
   ojd controller show 2DC8:301D > show.txt
   ojd controller capture 2DC8:301D --duration 20 --json > capture.jsonl
   ```

4. During the capture, follow the [control order](#control-order), including each rear button.
5. Report where each rear button you pressed sits.

## T5 Ultimate 2 over Cable and Dongle (2DC8:6012)

1. Connect the Ultimate 2 by cable and run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > cable-hid.txt
   ioreg -p IOUSB -l -w0 > cable-usb.txt
   ojd controller list > cable-list.txt
   ojd controller show 2DC8:6012 > cable-show.txt
   ojd controller capture 2DC8:6012 --duration 20 --json > cable-capture.jsonl
   ```

2. Swap the cable for the dongle and run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > dongle-hid.txt
   ioreg -p IOUSB -l -w0 > dongle-usb.txt
   ojd controller list > dongle-list.txt
   ojd controller show 2DC8:6012 > dongle-show.txt
   ojd controller capture 2DC8:6012 --duration 20 --json > dongle-capture.jsonl
   ```

3. During each capture, follow the [control order](#control-order), including the four rear buttons.
4. Run the first command below in DInput mode and the second in Switch mode. In each capture, hold the pad still for 3 seconds, then tip it forward and back, roll it left and right, and turn it left and right.

   ```shell
   ojd controller capture 2DC8:6012 --duration 20 --json > dinput-motion.jsonl
   ojd controller capture 2DC8:6012 --duration 20 --json > switch-motion.jsonl
   ```

5. Report which button each rear button acts as (example: "upper left rear acts as L3").

## T6 Ultimate 2 Receiver and Dongle (2DC8:6013, 2DC8:3107)

1. Plug in the receiver, pad off.
2. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > 6013-off-hid.txt
   ioreg -p IOUSB -l -w0 > 6013-off-usb.txt
   ojd controller list > 6013-off-list.txt
   ojd controller show 2DC8:6013 > 6013-off-show.txt
   ojd controller capture 2DC8:6013 --duration 20 --json > 6013-off-capture.jsonl
   ```

3. Switch the pad on, and run the commands again with `on` in place of `off` in the file names.
4. Do both runs again with the dongle, using 3107 in place of 6013.
5. During each `on` capture, follow the [control order](#control-order).
6. Report the PID `ojd controller list` showed in each run.

## T7 Ultimate 2 and Pro 3 on 2DC8:310B

1. Connect the Ultimate 2 in the mode that shows 310B.
2. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > ultimate2-hid.txt
   ioreg -p IOUSB -l -w0 > ultimate2-usb.txt
   ```

3. With a Pro 3, do it again with `pro3-` in place of `ultimate2-`.
4. Report where each pad's mode switch was set.

No control order here. The product strings and `bcdDevice` in the files decide the mode.

## T8 Ultimate 3-Mode over Bluetooth in Xbox Mode (2DC8:901B)

1. Set the pad to Xbox mode.
2. Pair it over Bluetooth.
3. Run:

   ```shell
   ioreg -r -c IOHIDDevice -l -w0 > hid.txt
   ioreg -p IOUSB -l -w0 > usb.txt
   ojd controller list > list.txt
   ojd controller show 2DC8:901B > show.txt
   ojd controller capture 2DC8:901B --duration 20 --json > capture.jsonl
   ```

4. During the capture, follow the [control order](#control-order).

## T9 Watchdog with 2DC8:310A and 2DC8:6012 Served

1. Connect the Ultimate 2C dongle (310A).
2. Run `ojd controller show 2DC8:310A`, and check that OJD serves it.
3. Don't touch any control. Run these (each line saves the time and the USB bus state):

   ```shell
   { date; ioreg -p IOUSB -l -w0; } > 310A-0min.txt
   sleep 300; { date; ioreg -p IOUSB -l -w0; } > 310A-5min.txt
   ojd controller suspend 2DC8:310A > 310A-suspend.txt
   sleep 10; { date; ioreg -p IOUSB -l -w0; } > 310A-suspended-10s.txt
   sleep 50; { date; ioreg -p IOUSB -l -w0; } > 310A-suspended-60s.txt
   ojd controller resume 2DC8:310A > 310A-resume.txt
   ojd controller list > 310A-list-after.txt
   ```

4. Do it again with the Ultimate 2, using 6012 in place of 310A.
5. Report whether each pad worked again after `resume` without reconnecting it.

No control order here.

## Further Reading

- [Test a Tester Build](tester-builds.md)
- [8BitDo Ultimate 2](8bitdo-ultimate-2.md)
- [8BitDo Ultimate 2C](8bitdo-ultimate-2c.md)
- [Command Line](../../wiki/Command-Line.md)
