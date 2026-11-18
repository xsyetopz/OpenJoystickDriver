# Test the SCUF Envision Pro

Wired Envision Pro: HID 2E95:434D, with hardware-recorded descriptor and element evidence for report 6 (issue 33). SCUF 2E95:0504 is a separate GIP identity.

Mapped: X/Y left stick, Z/Rz right stick, Rx/Ry triggers, buttons 1-10, hat. Unclaimed: buttons 11-19, physical output.

## Validate the Record and Parser

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/2e95/2e95-434d.plist \
  --validate-only
swift test --filter SCUFEnvisionParserTests
```

Expect `RECORD_VALIDATION result=valid`. Tests cover report-ID filtering, axis layout, button limit, hat diagonals and neutral, other-controller fallback.

## Verify Hardware

1. Connect by wire; capture identity and macOS version on the IOHID physical HID path.
2. Check only report 6 changes normalized state.
3. Move both sticks to every edge; press each trigger alone.
4. Press buttons 1-10 and each D-pad direction.
5. Check neutral, disconnect, reconnect.

Record buttons 11-19 unassigned. Not verified: paddles, side buttons, rumble, lighting, wireless, other identities.
