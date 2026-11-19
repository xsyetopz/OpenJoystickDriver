# Test the SCUF Envision Pro

This page covers the wired Envision Pro, HID 2E95:434D. Its descriptor and its report 6 were recorded from real hardware (issue 33). SCUF 2E95:0504 is a different, GIP identity.

What OJD maps and what it leaves alone:

| Mapped | Left alone |
| --- | --- |
| X/Y as the left stick, Z/Rz as the right stick, Rx/Ry as the triggers, buttons 1-10, the hat (D-pad) | Buttons 11-19, rumble and lights |

## Check the Record and Parser

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/2e95/2e95-434d.plist \
  --validate-only
swift test --filter SCUFEnvisionParserTests
```

Expect `RECORD_VALIDATION result=valid`. The tests check that OJD keeps only report 6, reads the stick and trigger layout, stops at button 10, reads the D-pad diagonals and its rest position, and that other Generic HID controllers still get the default layout.

## Check on Hardware

1. Plug it in with a cable. Write down its identity and the macOS version on the IOHID physical HID road.
2. Check that only report 6 changes what OJD reads.
3. Push both sticks to every edge, and press each trigger by itself.
4. Press buttons 1-10 and each D-pad direction.
5. Check the rest position, unplugging, and plugging back in.

Write down that buttons 11-19 do nothing. Not checked: paddles, side buttons, rumble, lights, wireless, other identities.
