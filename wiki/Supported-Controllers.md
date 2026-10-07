# Supported Controllers

This page lists the controllers that people tested with OpenJoystickDriver (OJD), explains what each tier means, and describes how OJD treats clone controllers and generic HID controllers.

> **Note:** This page applies to OpenJoystickDriver 0.6.0-alpha.1 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

Xbox and PlayStation names in the UI are trademarks of Microsoft and Sony. This project is not affiliated with either.

## Contents

- [Supported Controllers](#supported-controllers-1)
- [Clone and Fake Controllers](#clone-and-fake-controllers)
- [Generic HID Controllers](#generic-hid-controllers)
- [Further Reading](#further-reading)

## Supported Controllers

This section sorts controllers into three tiers. The tiers are a documentation classification. The app shows no tier and no warning. A tier records how much hardware testing confirms a controller. Official and Community-verified mean that people tested the controller on real hardware and it worked. Unverified means that nobody confirmed the controller yet. Somebody verified a controller only in the connection mode that they tested. The other modes have no verification and may work. A controller that works over USB may not work over Bluetooth or a dongle. For more information, see [Connection types](Connecting-Controllers.md#connection-types).

### Official

The maintainer owns and tests these controllers.

| Controller | Connection mode tested |
| --- | --- |
| Sony DUALSHOCK 4 (v2) | Not recorded here |
| Sony DUALSHOCK 3 (CECHZC2) | Not recorded here |
| GameSir G7 SE | Not recorded here |
| Razer Wolverine (V1) Tournament Edition | Not recorded here |

The maintainer says that a few more controllers belong in this tier. This list names only the four that the maintainer confirmed.

The DUALSHOCK 3 does not connect over Bluetooth on macOS 27.0. The test stored the Mac's Bluetooth address in the controller over USB, and the controller then reached the Mac. macOS requires authentication before it accepts a Bluetooth HID connection. It asks for a passcode, which the DUALSHOCK 3 cannot answer, and pairing times out. Use the DUALSHOCK 3 with a USB cable.

### Community-Verified

A tester used the controller on real hardware, and it worked. The table names the mode that the tester used.

| Controller | VID:PID | Mode tested | What works | Not tested |
| --- | --- | --- | --- | --- |
| 8BitDo Ultimate 2C Wireless | `2DC8:310A` | 2.4 GHz dongle, XInput mode | Buttons, sticks, triggers at rest, D-pad, stick clicks, rumble | Not recorded |
| ZD Ultimate Legend | `413D:2204` | 2.4 GHz dongle, XInput mode | Input, OJD rumble, back-button keyboard bindings, mode switching | Not recorded |

Two testers tested the 8BitDo Ultimate 2C Wireless on tester build `1.5.71`. One tester (gornobatov) tested the ZD Ultimate Legend on macOS 26.7.1. For the 8BitDo details, see [the test record](../docs/testing/8bitdo-ultimate-2c.md).

The 8BitDo Ultimate 2C Wireless has a different VID:PID in each mode. The Bluetooth mode `2DC8:301B` and the HID receiver mode `2DC8:301C` have no verification. They may work.

### Unverified

OJD includes a built-in catalog of 696 controller records. The Unverified tier is every catalog controller that this page does not list as Official or Community-verified. A record does not prove that the controller works. Nobody tested these controllers on real hardware. The catalog includes the NVIDIA SHIELD controllers of 2015 (`0955:7210`) and 2017 (`0955:7214`). On macOS the 2017 controller sends input only, with no rumble.

An unverified controller may work, may partly work, or may not work. The tier does not mean that the controller is broken or fake.

To find out whether your controller is in the catalog:

1. Connect the controller.
1. Open the **Controllers** pane in the OJD settings window.
1. Look for your controller in the list.

You can also run this command:

```shell
ojd controller list
```

If the controller appears, OJD has a record for it or reads it as a generic HID controller. If it does not appear, see [Controller not detected](Troubleshooting.md). A controller without a record may still work as a generic HID controller. For more information, see [Generic HID controllers](#generic-hid-controllers).

OJD leaves some gamepads to macOS. OJD does not publish a virtual controller for them.

### Report a Result

If you test a controller, tell the maintainer which mode you used and what worked. For more information, see [Reporting a bug](Reporting-a-Bug.md).

## Clone and Fake Controllers

Some controllers look like a Sony or Microsoft controller but use a different chip and a different identity. OJD identifies a controller by its VID:PID, not by its shape or its name on the box. A clone with a different VID:PID is a different device to OJD. For more information, see [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).

Clones often send data in a different format, so the driver for the original controller may read them wrongly. Do not report a clone under the name of the original controller.

### Known Clones

| Controller | Copies | Notes |
| --- | --- | --- |
| Zhongqing ZQDZ-P3-BT-3D-FZ-V2.0 | PS3 controller | The maintainer owns this fake. The chip is not identified. |
| Ant Esports GP100 | PS3 controller | A Shanwan PS3 clone. VID:PID `2563:0575` in PS3/PC mode. |

The Ant Esports GP100 starts in XInput mode. In that mode macOS sees no input. To switch it to PS3/PC mode, hold **Select** and **B** while you connect it. One tester reports **Start** and **B** instead. For more information, see [the Shanwan test record](../docs/testing/ps3-third-party.md).

## Generic HID Controllers

OJD can read some HID gamepads that are not in its catalog. It reads the report descriptor that the controller sends. Generic HID support is not a fallback for a known controller. A controller with a record always uses its own driver, and OJD does not retry a failing known controller as generic HID.

### What Works

Generic HID support reads these controls:

- Buttons 1 to 11 only. These map to south, east, west, north, LB, RB, view, menu, L3, R3, and guide.
- Two sticks.
- Two triggers.
- One eight-position D-pad hat.

Generic HID support has no rumble and no lighting. Buttons above 11 do not map. Paddles and other extra controls need a controller record.

### When OJD Refuses a Controller

OJD accepts a controller as generic HID only if its descriptor passes strict checks:

- The descriptor has a Joystick, Game Pad, or Multi-axis Controller collection.
- That collection has a stick or hat input and a button input.
- The descriptor has no unsupported or inconsistent items.

If a controller fails a check, OJD does not use it. The `status` command lists the controller as unbound and gives a reason. Run it with this command:

```shell
ojd status
```

For more information about `ojd`, see [Using the command line](Command-Line.md).

Some controllers are not standard. Their descriptor may put sticks or triggers on unusual axes. These controllers need a record.

## Further Reading

- [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id)
- [Connection types](Connecting-Controllers.md#connection-types)
- [Game and app compatibility](Playing-Games.md)
- [Reporting a bug](Reporting-a-Bug.md)
