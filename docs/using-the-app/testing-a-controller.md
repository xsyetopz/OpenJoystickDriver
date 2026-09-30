# Testing a controller

The Input Test window shows live input from a controller and lets you test rumble and lighting.

## Open the window

1. Open the **Controllers** pane.
1. Select a controller.
1. Click **Open Input Test...**.

OJD uses one Input Test window. The title is "Input Test" followed by the controller name. Closing the window stops sampling and any running output test. The toolbar has **Refresh Controller**.

## Status

The window header shows a status and the connection, protocol, and VID:PID. The status is one of these:

- **Ready**
- **Starting...**
- **Input active**
- **Input interrupted**
- **Controller disconnected**
- **Input Monitoring permission required**
- **Input unavailable**
- **Failed**

For **Input Monitoring permission required**, see [Permissions](../permissions-and-security/permissions.md).

## Groups

The window has no tabs. It shows one scrolling page with these groups.

### Live input

Shows sticks, the D-pad, face buttons, bumpers, triggers, stick buttons, and extra buttons. Each control shows **Pressed** or **Released**. Button names follow the virtual controller profile.

### Axis values

Shows **Left X**, **Left Y**, **Right X**, and **Right Y**, plus the triggers.

### Motion calibration

For controllers with a gyroscope. Keep the controller still while OJD collects the gyro bias. The buttons are **Refresh**, **Start calibration**, **Pause**, and **Reset**. Collection continues after you close the window. Click **Pause** to stop it. Motion calibration needs an enabled profile for the controller. Not verified: whether the calibration survives a restart of OJD.

### Rumble

Shows only when the controller supports rumble. Otherwise it shows **Rumble is not supported by this controller.**

1. Set the strength of each motor with its slider. The range is 0 to 255. Some motors only switch on and off.
1. Set **Duration**. The range is 100 to 2000 ms. The default is 300 ms.
1. Click **Test Rumble**.

Click **Stop** to end the test early. The group shows **Done** or **Failed**. If the controller rejects the test, the group shows **The controller rejected this output test.**

### Lighting

Shows only the controls that the controller supports. Otherwise it shows **Lighting controls are not available for this controller.** The controls are **Player indicator**, **Color**, and **Brightness**. Click **Apply** beside a control to send it.

## Further reading

- [Rumble and lighting](../playing-games/rumble-and-lighting.md)
- [Controllers pane](controllers-pane.md)
- [Controller not detected](../troubleshooting/controller-not-detected.md)
