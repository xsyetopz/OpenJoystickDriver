# Testing a Controller

The Input Test window shows live input from a controller and tests rumble and lighting.

## Open the Input Test Window

Click **Controllers** in the sidebar, select a controller, and click **Open Input Test**.

![The Controllers area. A red arrow points to Working under the controller's name. A second arrow points to Open Input Test, which shows each press live](../docs/screenshots/steps/controller-working.png)

You can also choose **Controller** > **Test Input**, or **Test Input** in the controller's submenu of the menu-bar icon.

![The controller's submenu in the menu bar. A red arrow points to Test Input, which opens a window that shows each press live](../docs/screenshots/steps/test-input.png)

Closing the window stops reading input and any running output test.

## Read the Status

The header shows the status, the connection, the protocol, and the controller's ID. The status is **Ready**, **Starting...**, **Input active**, **Input interrupted**, **Controller disconnected**, **Input Monitoring permission required**, **Input unavailable**, or **Failed**. For the permission status, see [Permissions](Permissions-and-Security.md#permissions).

## Guided Check

While input is active, **Guided Check** asks for each control, one at a time. A step ends when the control leaves rest, when another control moves first, or when you click **Skip**. Release a control you hold at the start of a step before it counts. Closing the window or changing the controller stops the check.

At the end, a sheet lists what each control did:

- **Save** writes the check document where you choose.
- **Copy** copies it.
- **Open Issue** saves the document to Downloads and opens the support form. Attach the saved file to the issue.
- **Validate** appears after a check in which every control responded. It shows the full text, which holds no serial number, Bluetooth address, user name, or path. Click **Confirm** to open the validation form.

`ojd controller check` runs the check in Terminal. See [Command Reference](Command-Reference.md).

## Use the Groups

The window is one scrolling page with these groups.

### Live Input

Sticks, D-pad, buttons, and triggers show their state. Button names follow the [virtual gamepad kind](Glossary.md#terms).

### Motion Calibration

This group appears for controllers with a gyroscope. Keep the controller still while OJD measures its resting offset. Use **Start Calibration**, **Pause**, and **Reset**. Collection continues after you close the window. It needs an enabled [profile](Glossary.md#terms) for the controller. It is untested whether the calibration survives a restart of OJD.

### Recalibrate

Use **Recalibrate** when a stick drifts or never reaches full range. Each step reads the controller for about two seconds.

- **Measure Rest**: release the sticks and triggers.
- **Measure Circle**: roll each stick around its full circle.
- **Measure Triggers**: press each trigger all the way in.
- **Measure Gyro**: keep the controller still. A controller without a gyroscope skips this.

OJD stores the values in the record for the controller's model and applies them before profile mapping. **Reset** removes them. `ojd controller calibrate CONTROLLER sticks` does the same in Terminal.

### Rumble

Drag each motor's slider (0 to 255), set **Duration** (100 to 2000 ms, default 300), and click **Test Rumble**. Click **Stop** to end the test early. A controller with no motor shows **Rumble is not supported by this controller.**

### Lighting

This group appears only for a controller with lighting. Set **Player indicator**, **Color**, or **Brightness**, then click **Apply**.

## Further Reading

- [Rumble and Lighting](Playing-Games.md#rumble-and-lighting)
- [Controllers Area](Using-the-App.md#controllers-area)
- [Controller Is Not Detected](Troubleshooting.md#if-a-controller-isnt-detected)
