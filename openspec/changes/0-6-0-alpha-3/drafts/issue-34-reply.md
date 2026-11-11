Thanks for the patches and the testing.

The Ultimate 2C layouts for `2DC8:301B` (Bluetooth LE) and `2DC8:301C` (2.4 GHz receiver, DInput) come from recorded captures. The results, with the capture file behind each row, are in `docs/testing/8bitdo-ultimate-2c.md`.

Two things your patch assumed that the captures show differently:

- Over Bluetooth LE, L4 sets bit 2 and R4 sets bit 5 of the button bytes, so each rear button has its own bit there. As `2DC8:301C`, an unassigned R4 sets bit 5.
- The Bluetooth LE battery byte reads 0 in every capture.

To check this on your pad, install the tester build I send you, as [Test a tester build](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/docs/testing/tester-builds.md) shows, and run:

```
ojd controller list
ojd controller capture 2DC8:301B --duration 60 > ultimate-2c-301b.txt
ojd diagnose --output ultimate-2c-support.txt
```

While the capture runs, press each control once in this order: A, B, X, Y, LB, RB, LT, RT, View, Menu, Home, L3, R3, D-pad up, right, down, left, both sticks fully around. Read `ultimate-2c-support.txt` before you share it, then attach both files.

Tell me which control, if any, still reads wrong.
