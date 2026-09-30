# Game does not see the controller

This article explains what to check when a controller works in OpenJoystickDriver (OJD) but not in a game or app.

## Check OJD first

1. Open the **Input Test** window for the controller. For more information, see [Testing a controller](../using-the-app/testing-a-controller.md).
1. Press buttons. If **Input Test** shows no input, see [Controller is not detected](controller-not-detected.md).
1. In **Overview**, check **Accessibility**. OJD needs it to publish the virtual controller.

## Understand why apps differ

OJD publishes a virtual controller. Each app reads it with its own API. One tester saw apps that use the Apple Game Controller framework, the browser Gamepad API, or **System Settings** read it. The maintainer did not check this. Apps that use SDL may not read it.

OJD cannot add SDL to other apps. Each app ships its own SDL version.

One tester saw these results with the Xbox virtual profile. This is not a guarantee.

| App | Result |
| --- | --- |
| Steam | Shows a phantom controller with no input |
| CrossOver and Wine | No controller |
| RPCS3 | Sees a controller, no input |
| OpenEmu | Buttons map to wrong controls |

## Try the other virtual profile

The design of OJD is to pick the virtual profile by itself. Use this step only to find out whether the profile is the cause. If a profile fixes a game, report it.

1. In **Controllers**, select the controller.
1. In **Advanced**, find **Virtual HID profile**. It appears only for controllers that OJD publishes.
1. Choose **Automatic** or one of the two profiles.
1. Test the game again.

OpenEmu worked with the `hid-generic` profile in the same test. Steam with that profile was erratic and slow to respond. The override applies to every controller of that model.

## Try a different controller mode

Some controllers have a Switch Pro mode. In that mode macOS reads the controller itself, and OJD does not publish a virtual controller. One tester saw RPCS3, the browser, and **System Settings** work in that mode. HD rumble in that mode drives only the linear haptics. Not verified for other controllers.

For more information, see [Game and app compatibility](../playing-games/game-and-app-compatibility.md).

## Further reading

- [How games see your controller](../playing-games/how-games-see-your-controller.md)
- [Known issues](known-issues.md)
- [Reporting a bug](reporting-a-bug.md)
