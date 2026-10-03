# Playing games

This page explains how games and apps see your controller through OpenJoystickDriver (OJD), which games and apps work, and what to expect from rumble.

## Contents

- [How games see your controller](#how-games-see-your-controller)
- [Game and app compatibility](#game-and-app-compatibility)
- [Rumble and lighting](#rumble-and-lighting)
- [Further reading](#further-reading)

## How games see your controller

Games do not read your physical controller. OJD reads it and publishes one virtual controller for each physical controller. Games read the virtual controller. The virtual controller uses one of two profiles.

### Virtual controller profiles

| Profile | Shown to games as | VID:PID | Rumble |
| --- | --- | --- | --- |
| `hid-xbox-one-s-bt` | Xbox Wireless Controller, Microsoft, Bluetooth | `045E:02FD` | Accepts rumble output |
| `hid-generic` | OpenJoystickDriver Generic HID Gamepad, USB | `1209:4A4F` | Input only |

The `hid-xbox-one-s-bt` profile is an approximation of an Xbox controller. It is not a byte-exact copy of a real controller. The `hid-generic` profile has 16 buttons and no hat. The D-pad uses four of the 16 buttons.

### Automatic selection

OJD picks a profile for each controller model in this order:

1. The override that you set for the model, if the profile fits the controller.
1. The `hid-xbox-one-s-bt` profile, if it fits the main controls of the controller.
1. The `hid-generic` profile.

The choice does not depend on the game, the macOS version, or the vendor. In current builds, the code suggests that OJD chooses the Xbox profile for most controllers. Not verified for every model.

OJD does not publish a virtual controller if macOS already handles the controller natively. The controller detail shows this state as **Left to macOS**.

### Change the profile for a model

OJD is designed to choose the profile for you. You do not need a different setting for each game. Change the profile only to test a problem, and report the result so that the automatic choice can improve. For more information, see [Reporting a bug](Reporting-a-Bug.md).

1. Open the **Controllers** pane.
1. Select your controller.
1. Expand **Advanced**.
1. In **Virtual HID profile**, select a profile.

Select **Automatic** to remove the override. The override applies to every connected controller of the same model. For more information, see [Controllers pane](Using-the-App.md).

## Game and app compatibility

This section lists which games and apps read the OJD virtual controller, based on tester results.

> [!NOTE]
> These results come from one tester (gornobatov) on macOS 26.7.1 with a ZD Ultimate Legend dongle and the `045E:02FD` Xbox profile. The maintainer has not verified them on hardware. They are not a guarantee.

Games read controllers through different programming interfaces. The interface decides whether a game sees the OJD virtual controller. OJD cannot add support to another app. For example, each app that uses SDL includes its own SDL version.

### Results by interface

| Interface | App | Xbox profile result |
| --- | --- | --- |
| OJD | Input Test | Works |
| macOS | Game Controllers in **System Settings** | Works |
| Browser | Gamepad API | Works |
| Apple Game Controller framework | Silksong (GOG) | Works after you turn on its native gamepad or MFi options |
| Native macOS games | Non-Steam native games | Works |
| SDL | Steam | Does not work. Shows a "Gamepad 1" with no input |
| Wine | CrossOver | Does not work. Sees no controller |
| SDL | RPCS3 | Does not work. Sees "Xbox One S Controller" with no input |
| IOHIDManager or SDL2 | Super Meat Boy, Cuphead, LEGO Marvel's Avengers, older Unity or Feral ports | Does not work. These games do not detect the controller |

### Generic HID profile results

| App | Generic HID profile result |
| --- | --- |
| OpenEmu | Works. The Xbox profile maps buttons wrongly. |
| Steam | Erratic and slow to respond |

OJD is designed to make one automatic choice work across these interfaces. The failures above are known issues, not settings that you must change. For more information, see [How games see your controller](#how-games-see-your-controller).

### Workaround for one controller

The tester switched the ZD Ultimate Legend itself to Switch Pro mode (`057E:2009`). In that mode macOS handles the controller natively. The controller detail shows **Left to macOS**, and OJD does not publish a virtual controller. RPCS3, the browser, and System Settings then work. HD Rumble in that mode drives only the linear haptics.

Not verified: this workaround for other controllers.

## Rumble and lighting

This section explains what reaches your physical controller when a game sends rumble.

### Rumble from games

The `hid-xbox-one-s-bt` virtual controller accepts rumble output. When a game sends rumble, OJD turns it into one short rumble command for the physical controller. OJD sends a stop command when the rumble ends. The maintainer has not verified rumble in games on hardware.

Only rumble reaches the physical controller. OJD does not pass lightbar or lighting commands from games to the controller. The `hid-generic` profile has no rumble.

The controller must support rumble. If it does not support a motor, OJD drops that channel. Controllers that use Generic HID have no rumble.

### Rumble from Input Test

Input Test has its own **Rumble** and **Lighting** groups. They talk to the controller directly and do not use a game. For more information, see [Testing a controller](Testing-a-Controller.md).

### Identical controllers

Known issue: if two controllers have the same VID:PID, rumble from games and from System Settings does not reach either controller. Rumble in Input Test still works.

## Further reading

- [Game does not see the controller](Troubleshooting.md)
- [Known issues](Known-Issues.md)
