# Test The SCUF Envision Pro

The wired SCUF Envision Pro record is exact HID identity `2E95:434D`. Issue 33 provides hardware-recorded descriptor and element evidence for report 6. OJD maps X/Y to the left stick, Z/Rz to the right stick, Rx/Ry to independent triggers, buttons 1–10, and the standard hat. Buttons 11–19 and physical output are not claimed. SCUF `2E95:0504` remains an independent GIP identity.

## Validate The Record And Parser

Run from the repository root:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/2e95/2e95-434d.json \
  --validate-only
swift test --filter SCUFEnvisionParserTests
```

The record validation must report `RECORD_VALIDATION result=valid`. The tests cover report-ID filtering, the exact axis layout, button limit, hat diagonals and neutral, and the unaffected descriptor-driven fallback for other controllers.

## Verify Hardware

Connect by wire and capture the controller's runtime identity. Test on the IOHID physical HID path and record the macOS version. Confirm that only report 6 changes normalized state. Exercise both sticks to every edge, each trigger independently, buttons 1–10, all D-pad directions, neutral, disconnect, and reconnect.

Record buttons 11–19 diagnostically without assigning meanings. Do not claim paddles, side buttons, rumble, lighting, wireless behavior, or another SCUF identity until a separate hardware record establishes that surface.
