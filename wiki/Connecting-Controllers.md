# Connecting Controllers

This page explains how USB, Bluetooth, and 2.4 GHz dongle connections differ for OpenJoystickDriver (OJD), how to read the VID:PID of your controller, and how the Xbox USB driver extension works.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [Connection Types](#connection-types)
- [Finding Your Controller ID](#finding-your-controller-id)
- [Xbox USB Driver Extension](#xbox-usb-driver-extension)
- [Further Reading](#further-reading)

## Connection Types

A controller can connect in more than one way. Each mode has its own VID:PID, and OJD treats each mode as a separate device. A controller that works in one mode may not work in another mode. For more information, see [Supported controllers](Supported-Controllers.md).

### Modes

| Mode | What OJD sees |
| --- | --- |
| USB | The controller, with the VID:PID of the wired mode. |
| Bluetooth | The controller, with the VID:PID of the Bluetooth mode. |
| 2.4 GHz dongle | The dongle, with its own VID:PID. |

Some controllers change their VID:PID when you change mode. For example, the 8BitDo Ultimate 2C Wireless uses `2DC8:310A` with its 2.4 GHz dongle in XInput mode. It uses `2DC8:301B` over Bluetooth and `2DC8:301C` with its HID receiver.

### Dongles

A dongle is a separate device from the controller. A dongle problem is not the same as a controller problem. When you report a problem, give the VID:PID of the dongle. For more information, see [Reporting a bug](Reporting-a-Bug.md).

### Bluetooth

OJD never reconnects a Bluetooth controller by itself. To disconnect a controller, select **Disconnect Wireless Controller...** in the controller detail. Then reconnect the controller by hand.

## Finding Your Controller ID

The VID:PID is the vendor ID and product ID that identify one controller model. A report without a VID:PID is hard to use. Each connection mode has its own VID:PID. For more information, see [Connection types](#connection-types).

### Read the ID For a USB Controller

1. Connect the controller by USB.
1. Open **System Information**.
1. Select **USB** in the sidebar.
1. Select your controller.
1. Read **Vendor ID** and **Product ID**.

The values appear with a `0x` prefix. For example, `0x045e` and `0x02d1` mean `045E:02D1`.

You can also run this command in Terminal:

```shell
system_profiler SPUSBDataType
```

### Read the ID For Any Connection

Use this method for a Bluetooth controller. Bluetooth controllers do not appear in the USB list.

1. Open the OJD settings window.
1. Open **Settings**.
1. Turn on **Enable Developer Tools**.
1. Open the **Developer Tools** pane.
1. Select your controller.

The pane shows the controller details, including its USB ID, connection type, and endpoints.

## Xbox USB Driver Extension

OJD has one DriverKit system extension, `com.openjoystickdriver.XboxUSBDevice`. It is embedded in the app and owns the USB interfaces of genuine Xbox One and Xbox Series controllers. It only serves Xbox One and Xbox Series controllers that connect by USB with one of these VID:PID values:

- `045E:02D1`
- `045E:02DD`
- `045E:02E3`
- `045E:02EA`
- `045E:0B00`
- `045E:0B0A`
- `045E:0B12`

Every other controller does not need the extension. OJD reads those controllers directly from the app. The extension does not publish a virtual controller. The app publishes it.

A build whose app profile has no `userclient-access` grant for the extension has no driver extension, so **Driver Extensions** in **System Settings** lists nothing from OJD. See [Build options and limits](Building-from-Source.md).

### Approve the Extension

Do these steps only if you use one of the controllers above.

1. Open the OJD settings window.
1. Open the **Overview** pane.
1. Find the **Xbox USB Driver** card. It shows **Approval needed** until you approve the extension.
1. Click **Open System Settings**. OJD opens the **Login Items & Extensions** settings.
1. Approve the OpenJoystickDriver extension in **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions**.

When the card shows **Ready**, the extension is active. If the card shows **Needs attention**, click **Repair Xbox USB Driver** when that button appears.

## Further Reading

- [Supported controllers](Supported-Controllers.md)
- [Adding or changing a controller record](Controller-Records.md)
- [Controller not detected](Troubleshooting.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Build options and limits](Building-from-Source.md)
- [Overview pane](Using-the-App.md)
- [Security model](Permissions-and-Security.md)
