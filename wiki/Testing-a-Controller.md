# Testing a Controller

The Input Test window shows live input from a controller and lets you test rumble and lighting.

## Open the Window

1. Open the **Controllers** area.
2. Select a controller.
3. Click **Open Input Test...**.

OJD uses one Input Test window. The title is "Input Test" followed by the controller name. Closing the window stops sampling and any running output test. The toolbar has **Refresh**.

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

For **Input Monitoring permission required**, see [Permissions](Permissions-and-Security.md#permissions).

## Guided Check

**Guided Check** sits under the status while input is active. It asks for each control the controller declares, one at a time, with the step text and a **Skip** button. A step ends when that control leaves rest, when another control moves first (the result names it), or when you click **Skip**. A control held when its step starts counts only after you release it. A stick or trigger ends its step when it returns to rest and keeps the range it showed. Closing the window or changing the controller cancels the check.

The end sheet lists what each control did and has these buttons:

- **Save** writes the `ControllerCheck` document where you choose.
- **Copy** puts the document on the pasteboard.
- **Open Issue** saves the document in the Downloads folder, shows it in the file viewer, and opens the `controller-support.yml` form with the version, VID:PID, connection, and mode filled in. The address holds no report body; attach the saved file to the issue.
- **Validate** appears only after a check in which every control responded. It opens a sheet with the full text, which holds no serial number, unit ID, Bluetooth address, user name, or path, and the address it goes to. **Confirm** then opens the prefilled `controller-validation.yml` form.

`ojd controller check` does the same in a terminal; see [Command Reference](Command-Reference.md).

## Groups

The window has no tabs. It shows one scrolling page with these groups.

### Live Input

Shows sticks, the D-pad, face buttons, bumpers, triggers, stick buttons, and extra buttons. Each control shows **Pressed** or **Released**. Button names follow the [virtual gamepad kind](Glossary.md#terms). **Left stick** and **Right stick** show the X and Y value of each stick, and each trigger shows its value.

### Motion Calibration

For controllers with a gyroscope. Keep the controller still while OJD collects the gyro bias. The buttons are **Refresh**, **Start calibration**, **Pause**, and **Reset**. Collection continues after you close the window. Click **Pause** to stop it. Motion calibration needs an enabled [profile](Glossary.md#terms) for the controller. Not verified: whether the calibration survives a restart of OJD.

### Recalibrate

Measures where each stick rests, how far it reaches, and where each trigger rests and ends, for a controller whose sticks drift or never reach full. Each step reads the controller for about two seconds:

- **Measure Rest**: release the sticks and triggers.
- **Measure Circle**: roll each stick around its full circle.
- **Measure Triggers**: press each trigger all the way in.

OJD stores the values in your record of the controller's model and applies them before profile mapping. A control that did not move keeps its stored value, and the group names it. **Reset** removes the stored values and the gyro offset. The model needs a record. `ojd controller calibrate CONTROLLER sticks` and `reset` do the same in a terminal; see [Command Reference](Command-Reference.md).

### Rumble

Shows the motors that the controller has. A controller with no motor shows **Rumble is not supported by this controller.**

1. Set the strength of each motor with its slider. The range is 0 to 255. Some motors only switch on and off.
2. Set **Duration**. The range is 100 to 2000 ms. The default is 300 ms.
3. Click **Test Rumble**.

Click **Stop** to end the test early. The group shows **Done** or **Failed**. If the controller rejects the test, the group shows **The controller rejected this output test.**

### Lighting

Shows only for a controller with lighting, and only the controls that the controller supports. The controls are **Player indicator**, **Color**, and **Brightness**. Click **Apply** beside a control to send it.

## Further Reading

- [Rumble and lighting](Playing-Games.md)
- [Controllers area](Using-the-App.md#controllers-area)
- [Controller not detected](Troubleshooting.md)
