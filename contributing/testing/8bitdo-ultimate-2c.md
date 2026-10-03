# 8BitDo Ultimate 2C Wireless

The Ultimate 2C Wireless enumerates as a different identity in each mode. Test and report each mode separately.

| Mode | VID:PID | Route | Status |
| --- | --- | --- | --- |
| 2.4 GHz dongle, XInput | `2DC8:310A` | `xbox.xusb` | Hardware-verified by two testers on `0.5.0-beta.4` tester build `1.5.71`: buttons, sticks, triggers at rest, D-pad, stick clicks, rumble |
| Bluetooth LE | `2DC8:301B` | `hid.descriptor` | Mapping confirmed on hardware from a patch ([#34](https://github.com/xsyetopz/OpenJoystickDriver/issues/34)); this build is not yet tested |
| HID receiver | `2DC8:301C` | `hid.descriptor` | Assumed to share the Bluetooth layout; not verified |

## Why Bluetooth needs a record

Over Bluetooth the controller advertises a standard GamePad descriptor. The generic mapping read it wrong: the right stick drove LT/RT, the triggers rested at half travel, and several buttons were shifted. Three properties of the descriptor cause this:

- the right stick is on `Z`/`Rz`, not `Rx`/`Ry`;
- the analog triggers are on Simulation page `0x02`: Accelerator is RT and Brake is LT;
- button usages follow Android order with gaps.

The record binds `hid.descriptor` with the same layout as the GameSir G7 SE:

| Button usage | Control |
| --- | --- |
| 1 | A |
| 2 | B |
| 4 | X |
| 5 | Y |
| 7 | LB |
| 8 | RB |
| 11 | View |
| 12 | Menu |
| 13 | Home |
| 14 | L3 |
| 15 | R3 |

Usages 3 and 6 are the rear buttons and 9 and 10 repeat the triggers as digital bits. They are not mapped.

## Procedure

Connect the controller in the mode under test, then confirm the route (`ojd` is the [command-line tool](../../docs/Command-Line.md), and `<controller>` is an ID from the list or its `VVVV:PPPP`):

```bash
ojd controller list
ojd controller show <controller>
```

In `show`, Bluetooth and the HID receiver should report the protocol `hid.descriptor`; the XInput dongle reports `xbox.xusb`. Then watch the controls:

```bash
ojd controller watch <controller>
```

With the controller at rest, both triggers must read 0. Move the right stick and confirm the triggers stay at 0. Press each button in the table and confirm the reported name matches the label on the controller. Report the result with the mode and VID:PID on [#34](https://github.com/xsyetopz/OpenJoystickDriver/issues/34).
