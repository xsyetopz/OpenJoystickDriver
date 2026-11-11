Thanks for the full raw capture.

Your report was a dead right stick on `2DC8:301B` with OJD running. With my pad on 0.6.0-alpha.2 the right stick follows `Z`/`Rz` and both triggers read 0 at rest (`evidence/2c-bluetooth-301b/ojd-watch-120s.txt`), so I cannot reproduce it. Could you retest on [0.6.0-alpha.2](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.6.0-alpha.2)?

Run these with the pad connected over Bluetooth LE, and sweep the right stick in full circles while the second command runs:

```
ojd controller show 2DC8:301B
ojd controller watch 2DC8:301B --duration 20
```

If the right stick still does nothing, also run:

```
ojd controller capture 2DC8:301B --duration 20 > right-stick.txt
ojd diagnose --output support.txt
```

Read `support.txt` before you share it, then attach both files.

On the rear buttons: the captures in `docs/testing/8bitdo-ultimate-2c.md` show L4 setting bit 2 and R4 setting bit 5 of the button bytes over Bluetooth LE, which is not the RB duplicate you saw. If your R4 still sends the RB bit, tell me how the rear buttons are assigned in the 8BitDo app.
