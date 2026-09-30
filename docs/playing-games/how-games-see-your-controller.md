# How games see your controller

This article explains the virtual controller that OpenJoystickDriver (OJD) publishes for games and apps.

Games do not read your physical controller. OJD reads it and publishes one virtual controller for each physical controller. Games read the virtual controller. The virtual controller uses one of two profiles.

## Virtual controller profiles

| Profile | Shown to games as | VID:PID | Rumble |
| --- | --- | --- | --- |
| `hid-xbox-one-s-bt` | Xbox Wireless Controller, Microsoft, Bluetooth | `045E:02FD` | Accepts rumble output |
| `hid-generic` | OpenJoystickDriver Generic HID Gamepad, USB | `1209:4A4F` | Input only |

The `hid-xbox-one-s-bt` profile is an approximation of an Xbox controller. It is not a byte-exact copy of a real controller. The `hid-generic` profile has 16 buttons and no hat. The D-pad uses four of the 16 buttons.

## Automatic selection

OJD picks a profile for each controller model in this order:

1. The override that you set for the model, if the profile fits the controller.
1. The `hid-xbox-one-s-bt` profile, if it fits the main controls of the controller.
1. The `hid-generic` profile.

The choice does not depend on the game, the macOS version, or the vendor. In current builds, the code suggests that OJD chooses the Xbox profile for most controllers. Not verified for every model.

OJD does not publish a virtual controller if macOS already handles the controller natively. The controller detail shows this state as **Left to macOS**.

## Change the profile for a model

OJD is designed to choose the profile for you. You do not need a different setting for each game. Change the profile only to test a problem, and report the result so that the automatic choice can improve. For more information, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).

1. Open the **Controllers** pane.
1. Select your controller.
1. Expand **Advanced**.
1. In **Virtual HID profile**, select a profile.

Select **Automatic** to remove the override. The override applies to every connected controller of the same model. For more information, see [Controllers pane](../using-the-app/controllers-pane.md).

## Further reading

- [Game and app compatibility](game-and-app-compatibility.md)
- [Rumble and lighting](rumble-and-lighting.md)
- [Game does not see the controller](../troubleshooting/game-does-not-see-the-controller.md)
