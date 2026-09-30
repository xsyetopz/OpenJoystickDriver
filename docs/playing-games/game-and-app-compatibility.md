# Game and app compatibility

This article lists which games and apps read the OpenJoystickDriver (OJD) virtual controller, based on tester results.

> [!NOTE]
> These results come from one tester (gornobatov) on macOS 26.7.1 with a ZD Ultimate Legend dongle and the `045E:02FD` Xbox profile. The maintainer has not verified them on hardware. They are not a guarantee.

Games read controllers through different programming interfaces. The interface decides whether a game sees the OJD virtual controller. OJD cannot add support to another app. For example, each app that uses SDL includes its own SDL version.

## Results by interface

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

## Generic HID profile results

| App | Generic HID profile result |
| --- | --- |
| OpenEmu | Works. The Xbox profile maps buttons wrongly. |
| Steam | Erratic and slow to respond |

OJD is designed to make one automatic choice work across these interfaces. The failures above are known issues, not settings that you must change. For more information, see [How games see your controller](how-games-see-your-controller.md).

## Workaround for one controller

The tester switched the ZD Ultimate Legend itself to Switch Pro mode (`057E:2009`). In that mode macOS handles the controller natively. The controller detail shows **Left to macOS**, and OJD does not publish a virtual controller. RPCS3, the browser, and System Settings then work. HD Rumble in that mode drives only the linear haptics.

Not verified: this workaround for other controllers.

## Further reading

- [Rumble and lighting](rumble-and-lighting.md)
- [Known issues](../troubleshooting/known-issues.md)
- [Game does not see the controller](../troubleshooting/game-does-not-see-the-controller.md)
