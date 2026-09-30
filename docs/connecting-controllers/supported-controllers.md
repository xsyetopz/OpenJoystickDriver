# Supported controllers

This article lists the controllers that people tested with OpenJoystickDriver (OJD) and explains what each tier means.

This article sorts controllers into three tiers. The tiers are a documentation classification. The app shows no tier and no warning. Somebody verified a controller only in the connection mode that they tested. The other modes have no verification and may work. A controller that works over USB may not work over Bluetooth or a dongle. For more information, see [Connection types](connection-types.md).

## Official

The maintainer owns and tests these controllers.

| Controller | Connection mode tested |
| --- | --- |
| Sony DUALSHOCK 4 (v2) | Not recorded here |
| Sony DUALSHOCK 3 (CECHZC1) | Not recorded here |
| GameSir G7 SE | Not recorded here |
| Razer Wolverine (V1) Tournament Edition | Not recorded here |

The maintainer says that a few more controllers belong in this tier. This list names only the four that the maintainer confirmed.

## Community-verified

A tester used the controller on real hardware, and it worked. The table names the mode that the tester used.

| Controller | VID:PID | Mode tested | What works | Not tested |
| --- | --- | --- | --- | --- |
| 8BitDo Ultimate 2C Wireless | `2DC8:310A` | 2.4 GHz dongle, XInput mode | Buttons, sticks, triggers at rest, D-pad, stick clicks, rumble | Not recorded |
| ZD Ultimate Legend | `413D:2204` | 2.4 GHz dongle, XInput mode | Input, OJD rumble, back-button keyboard bindings, mode switching | Not recorded |

Two testers tested the 8BitDo Ultimate 2C Wireless on tester build `1.5.71`. One tester (gornobatov) tested the ZD Ultimate Legend on macOS 26.7.1. For the 8BitDo details, see [the test record](../../contributing/testing/8bitdo-ultimate-2c.md).

The 8BitDo Ultimate 2C Wireless has a different VID:PID in each mode. The Bluetooth mode `2DC8:301B` and the HID receiver mode `2DC8:301C` have no verification. They may work.

## Unverified

OJD includes a built-in catalog of 696 controller records. The Unverified tier is every catalog controller that this article does not list as Official or Community-verified. A record does not prove that the controller works. Nobody tested these controllers on real hardware. The catalog includes the NVIDIA SHIELD controllers of 2015 (`0955:7210`) and 2017 (`0955:7214`). On macOS the 2017 controller sends input only, with no rumble.

An unverified controller may work, may partly work, or may not work. The tier does not mean that the controller is broken.

To find out whether your controller is in the catalog:

1. Connect the controller.
1. Open the **Controllers** pane in the OJD settings window.
1. Look for your controller in the list.

You can also run this command:

```shell
ojd controller list
```

If the controller appears, OJD has a record for it or reads it as a generic HID controller. If it does not appear, see [Controller not detected](../troubleshooting/controller-not-detected.md). A controller without a record may still work as a generic HID controller. For more information, see [Generic HID controllers](generic-hid-controllers.md).

OJD leaves some gamepads to macOS. OJD does not publish a virtual controller for them.

## Report a result

If you test a controller, tell the maintainer which mode you used and what worked. For more information, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).

## Further reading

- [Finding your controller ID](finding-your-controller-id.md)
- [Clone and fake controllers](clone-and-fake-controllers.md)
- [Game and app compatibility](../playing-games/game-and-app-compatibility.md)
