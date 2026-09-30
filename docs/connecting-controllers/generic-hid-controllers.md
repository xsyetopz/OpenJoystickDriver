# Generic HID controllers

This article explains what OpenJoystickDriver (OJD) supports for a controller that has no specific record.

OJD can read some HID gamepads that are not in its catalog. It reads the report descriptor that the controller sends. Generic HID support is not a fallback for a known controller. A controller with a record always uses its own driver, and OJD does not retry a failing known controller as generic HID.

## What works

Generic HID support reads these controls:

- Buttons 1 to 11 only. These map to south, east, west, north, LB, RB, view, menu, L3, R3, and guide.
- Two sticks.
- Two triggers.
- One eight-position D-pad hat.

Generic HID support has no rumble and no lighting. Buttons above 11 do not map. Paddles and other extra controls need a controller record.

## When OJD refuses a controller

OJD accepts a controller as generic HID only if its descriptor passes strict checks:

- The descriptor has a Joystick, Game Pad, or Multi-axis Controller collection.
- That collection has a stick or hat input and a button input.
- The descriptor has no unsupported or inconsistent items.

If a controller fails a check, OJD does not use it. The `status` command lists the controller as unbound and gives a reason. Run it with this command:

```shell
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless status
```

Some controllers are not standard. Their descriptor may put sticks or triggers on unusual axes. These controllers need a record.

## Further reading

- [Supported controllers](supported-controllers.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
