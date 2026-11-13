# Connecting Controllers

This page explains how USB, Bluetooth, and 2.4 GHz dongle connections differ for OpenJoystickDriver (OJD), how to read the VID:PID of your controller, and how the [Xbox USB driver](Glossary.md#terms) works.

## Contents

- [Connection Types](#connection-types)
- [Finding Your Controller ID](#finding-your-controller-id)
- [Xbox USB Driver](#xbox-usb-driver)
- [Further Reading](#further-reading)

## Connection Types

A controller can connect in more than one way. Each mode has its own VID:PID, and OJD treats each mode as a separate device. A controller that works in one mode may not work in another mode. For more information, see [Supported controllers](Supported-Controllers.md).

### Modes

| Mode | What OJD sees |
| --- | --- |
| USB | The controller, with the VID:PID of the wired mode. |
| Bluetooth | The controller, with the VID:PID of the Bluetooth mode. |
| 2.4 GHz dongle | The dongle, with its own VID:PID. |

Some controllers change their VID:PID when you change mode. For example, the 8BitDo Ultimate 2C Wireless uses `2DC8:310A` with its 2.4 GHz dongle in XInput mode. It uses `2DC8:301B` over Bluetooth, `2DC8:301D` wired in DInput mode and `2DC8:301C` with its HID receiver, which OJD treats as idle.

### Dongles

A dongle is a separate device from the controller. A dongle problem is not the same as a controller problem. When you report a problem, give the VID:PID of the dongle. For more information, see [Reporting a bug](Reporting-a-Bug.md).

### Bluetooth

OJD never reconnects a Bluetooth controller by itself. To disconnect a controller, click **Disconnect Wireless Controller...** in the controller detail. Then reconnect the controller by hand. For the Wii Remote, see [Wii Remote](Wii-Remote.md).

## Finding Your Controller ID

The VID:PID is the vendor ID and product ID that identify one controller model. A report without a VID:PID is hard to use. Each connection mode has its own VID:PID. For more information, see [Connection types](#connection-types).

### Read the ID For a USB Controller

1. Connect the controller by USB.
2. Open **System Information**.
3. Select **USB** in the sidebar.
4. Select your controller.
5. Read **Vendor ID** and **Product ID**.

The values appear with a `0x` prefix. For example, `0x045e` and `0x02d1` mean `045E:02D1`.

You can also run this command in Terminal:

```shell
system_profiler SPUSBDataType
```

### Read the ID For Any Connection

Use this method for a Bluetooth controller. Bluetooth controllers do not appear in the USB list.

1. Open **Settings**.
2. Open the **Advanced** pane.
3. Turn on **Enable Developer Tools** (needs the **All Controls** interface).
4. Select your controller in the developer tools below it.

The developer tools need the **All Controls** interface: set **Interface** to **All Controls** in **Settings** > **General**, or choose **View** > **All Controls**.
At **Simple**, they stay hidden.
The developer tools show the controller details, including its USB ID, connection type, and endpoints.

## Xbox USB Driver

The Xbox USB driver, `com.openjoystickdriver.XboxUSBDevice`, is a DriverKit driver that OJD installs. It is embedded in the app and owns the USB interfaces of genuine Xbox One and Xbox Series controllers. It only reads Xbox One and Xbox Series controllers that connect by USB with one of these VID:PID values:

- `045E:02D1`
- `045E:02DD`
- `045E:02E3`
- `045E:02EA`
- `045E:0B00`
- `045E:0B0A`
- `045E:0B12`

Every other controller does not need the driver. OJD reads those controllers directly from the app. The driver does not publish a [virtual gamepad](Glossary.md#terms). The app publishes it.

A build whose app profile has no `userclient-access` grant for the driver has no Xbox USB driver, so **Driver Extensions** in **System Settings** lists nothing from OJD. See [Build options and limits](Building-from-Source.md).

### Approve the Driver

Do these steps only if you use one of the controllers above.

1. Open the app window. Until you approve the driver, the banner below the toolbar shows **Xbox USB Driver** and **Open System Settings**.
2. Click **Open System Settings**. OJD opens the **Login Items & Extensions** settings.
3. Approve OpenJoystickDriver in **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions**.

When the driver is active, the banner disappears, and **Xbox USB Driver** in **Settings** > **Advanced** says **Installed**. If the driver needs repair, the banner shows **Repair Xbox USB Driver**. Click it.

![Settings, Advanced pane: the Xbox USB Driver section says that the driver is installed and ready](../docs/screenshots/settings-advanced.png)

## Further Reading

- [Supported controllers](Supported-Controllers.md)
- [Adding or changing a controller record](Controller-Records.md)
- [Controller not detected](Troubleshooting.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Build options and limits](Building-from-Source.md)
- [Using the app](Using-the-App.md)
- [Security model](Permissions-and-Security.md)
