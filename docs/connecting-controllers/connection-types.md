# Connection types

This article explains how USB, Bluetooth, and 2.4 GHz dongle connections differ for OpenJoystickDriver (OJD).

A controller can connect in more than one way. Each mode has its own VID:PID, and OJD treats each mode as a separate device. A controller that works in one mode may not work in another mode. For more information, see [Supported controllers](supported-controllers.md).

## Modes

| Mode | What OJD sees |
| --- | --- |
| USB | The controller, with the VID:PID of the wired mode. |
| Bluetooth | The controller, with the VID:PID of the Bluetooth mode. |
| 2.4 GHz dongle | The dongle, with its own VID:PID. |

Some controllers change their VID:PID when you change mode. For example, the 8BitDo Ultimate 2C Wireless uses `2DC8:310A` with its 2.4 GHz dongle in XInput mode. It uses `2DC8:301B` over Bluetooth and `2DC8:301C` with its HID receiver.

## Dongles

A dongle is a separate device from the controller. A dongle problem is not the same as a controller problem. When you report a problem, give the VID:PID of the dongle. For more information, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).

## Bluetooth

OJD never reconnects a Bluetooth controller by itself. To disconnect a controller, select **Disconnect Wireless Controller...** in the controller detail. Then reconnect the controller by hand.

## Further reading

- [Finding your controller ID](finding-your-controller-id.md)
- [Controller not detected](../troubleshooting/controller-not-detected.md)
