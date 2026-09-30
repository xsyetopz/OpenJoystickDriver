# Rumble and lighting

This article explains what reaches your physical controller when a game sends rumble.

## Rumble from games

The `hid-xbox-one-s-bt` virtual controller accepts rumble output. When a game sends rumble, OJD turns it into one short rumble command for the physical controller. OJD sends a stop command when the rumble ends. The maintainer has not verified rumble in games on hardware.

Only rumble reaches the physical controller. OJD does not pass lightbar or lighting commands from games to the controller. The `hid-generic` profile has no rumble.

The controller must support rumble. If it does not support a motor, OJD drops that channel. Controllers that use Generic HID have no rumble.

## Rumble from Input Test

Input Test has its own **Rumble** and **Lighting** groups. They talk to the controller directly and do not use a game. For more information, see [Testing a controller](../using-the-app/testing-a-controller.md).

## Identical controllers

Known issue: if two controllers have the same VID:PID, rumble from games and from System Settings does not reach either controller. Rumble in Input Test still works.

## Further reading

- [Known issues](../troubleshooting/known-issues.md)
- [Game and app compatibility](game-and-app-compatibility.md)
