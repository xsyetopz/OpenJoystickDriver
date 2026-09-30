# About OpenJoystickDriver

OpenJoystickDriver (OJD) is a macOS menu-bar app that reads game controllers and shows them to macOS games as a standard controller.

## How it works

OJD runs in your user session. It reads reports from a physical controller over USB, Bluetooth, or a 2.4 GHz dongle. It then publishes a virtual controller that games and apps can read.

The virtual controller uses one of two profiles. One profile is an Xbox Wireless Controller. The other profile is a generic gamepad. OJD selects one automatically. For more information, see [How games see your controller](../playing-games/how-games-see-your-controller.md).

OJD can also remap controls. A profile can send controller input as keyboard, pointer, or scroll events. For more information, see [About profiles](../remapping-controls/about-profiles.md).

## What OJD does not need

- OJD does not install a kernel extension.
- OJD does not need you to turn off System Integrity Protection (SIP).
- OJD does not need you to turn off Apple Mobile File Integrity (AMFI).

Only Xbox One and Xbox Series controllers on USB need an optional system extension. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

## What OJD is not

- OJD is not a guarantee that every game reads the virtual controller. Some apps that use SDL may not read it. For more information, see [Game and app compatibility](../playing-games/game-and-app-compatibility.md).
- OJD is beta software. Some controllers are not tested on real hardware. For more information, see [Supported controllers](../connecting-controllers/supported-controllers.md).

## Further reading

- [Installing OpenJoystickDriver](installing-openjoystickdriver.md)
- [Security model](../permissions-and-security/security-model.md)
