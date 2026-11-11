Could you capture every control of the GameSir G7 Pro through the dongle? The dongle's HID gamepad interface needs its own mode, and I add the controls only from a capture.

1. Install the tester build I send you, as [Test a tester build](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/docs/testing/tester-builds.md) shows.
2. With the dongle plugged in and the pad linked, run:
   ```
   ojd controller list
   ojd controller show 3537:1022
   ```
   Copy both outputs.
3. Some firmware shows the dongle as `3537:10A8`. Run `ojd controller list` again and tell me which identity appears: `3537:1022`, `3537:10A8`, or both.
4. Start a capture and press each control once, pausing about two seconds between presses:
   ```
   ojd controller capture 3537:1022 --duration 120 > g7-capture.txt
   ```
   Use `3537:10A8` in place of `3537:1022` if that is the identity listed. Order: A, B, X, Y, LB, RB, LT, RT (slowly, to full), View, Menu, Guide, L3, R3, D-pad up, right, down, left, both sticks around, then every extra and back button the pad has.
5. Write down the order you pressed them in.
6. Run:
   ```
   ojd diagnose --output support-g7.txt
   ```
   Read the file before you share it.
7. Attach the outputs, `g7-capture.txt` and your press order.
