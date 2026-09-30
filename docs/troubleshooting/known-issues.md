# Known issues

This article lists current OpenJoystickDriver (OJD) bugs and limits, with a workaround for each.

## Two global profiles for one controller model crash the app

If two profiles with global scope are active for the same controller model, OJD crashes at every start.

To recover:

1. Quit OJD.
1. Move `~/Library/Application Support/OpenJoystickDriver/RemappingProfiles.json` to another folder.
1. Open OJD.

OJD then opens with no profiles. Do not activate a second global profile for a model that already has one. For more information, see [App crashes or does not start](app-crashes-or-does-not-start.md).

## Rumble does not reach two identical controllers

When two controllers have the same VID:PID, rumble from games and from **System Settings** does not reach either controller. Rumble from the **Input Test** window works.

## Unplugging a USB controller can crash the app

If you unplug a USB controller or dongle while OJD runs, OJD may crash. It may also leave stale virtual controllers in **System Settings**. Restart OJD to clear them.

## The virtual controller override applies to every controller of a model

The virtual controller override in the controller detail applies to every connected controller with the same VID:PID. This is by design.

## Some apps do not read the virtual controller

Steam, CrossOver, RPCS3, and older games that use SDL2 or IOHIDManager may not read the virtual Xbox controller. For more information, see [Game and app compatibility](../playing-games/game-and-app-compatibility.md).

## Further reading

- [Game does not see the controller](game-does-not-see-the-controller.md)
- [Reporting a bug](reporting-a-bug.md)
