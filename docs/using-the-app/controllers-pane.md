# Controllers pane

The **Controllers** pane lists connected controllers and shows details and actions for the selected controller.

## The list

The list shows each connected controller. Click **Refresh controllers** to read the list again. If no controller appears, the pane shows **No controller connected**. For more information, see [Controller not detected](../troubleshooting/controller-not-detected.md).

## Controller details

Select a controller to see its details. The details include these fields when the controller reports them:

- **Published as**: the virtual controller identity that OJD shows to games. A controller that macOS handles itself shows **Native macOS gamepad, not published**.
- **Protocol**
- **Serial number**
- **Battery**, **Charging state**, and **Cable state**
- **USB VID/PID**: the vendor and product IDs. For more information, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).
- **Input endpoint** and **Output endpoint**
- **Active profile**

A field that the controller does not report shows **Not reported**.

## Actions

- **Open Input Test...** opens the test window. For more information, see [Testing a controller](testing-a-controller.md).
- **Disconnect from OpenJoystickDriver** pauses input, physical effects, and virtual output for this controller. The controller then shows **Suspended**. Click **Resume** to continue. **Open Input Test...** is off while the controller shows **Suspended**.
- **Disconnect Wireless Controller...** appears only for Bluetooth controllers. It closes the Bluetooth link. The controller stays disconnected until you connect it again by hand. OJD never reconnects Bluetooth by itself.

## Advanced section

The **Advanced** section appears for controllers that macOS does not handle itself. It contains the **Virtual HID profile** menu:

- **Automatic** lets OJD choose the virtual controller profile.
- **Xbox Wireless Controller (hid-xbox-one-s-bt)** forces the Xbox profile.
- **OpenJoystickDriver Generic HID Gamepad (hid-generic)** forces the generic profile.

The **Live profile** row shows the profile in use and its source: **Automatic**, **Override**, or **Automatic, override rejected**.

> [!NOTE]
> The override applies to every connected controller of the same model, because OJD stores it per VID:PID.

The change takes effect at once. **Updating virtual HID profile...** shows while it applies. If activation fails, OJD restores the previous profile and shows a message. For more information, see [How games see your controller](../playing-games/how-games-see-your-controller.md).

## Further reading

- [Testing a controller](testing-a-controller.md)
- [Connection types](../connecting-controllers/connection-types.md)
- [Known issues](../troubleshooting/known-issues.md)
