# Connecting controllers

This page explains how USB, Bluetooth, and 2.4 GHz dongle connections differ for OpenJoystickDriver (OJD), how to read the VID:PID of your controller, and how the Xbox USB driver extension works.

## Contents

- [Connection types](#connection-types)
- [Finding your controller ID](#finding-your-controller-id)
- [Xbox USB driver extension](#xbox-usb-driver-extension)
- [Further reading](#further-reading)

## Connection types

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

## Finding your controller ID

The VID:PID is the vendor ID and product ID that identify one controller model. A report without a VID:PID is hard to use. Each connection mode has its own VID:PID. For more information, see [Connection types](#connection-types).

### Read the ID for a USB controller

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

### Read the ID for any connection

Use this method for a Bluetooth controller. Bluetooth controllers do not appear in the USB list.

1. Open the OJD settings window.
1. Open **Settings**.
1. Turn on **Enable Developer Tools**.
1. Open the **Developer Tools** pane.
1. Select your controller.

The pane shows the controller details, including its USB ID, connection type, and endpoints.

## Xbox USB driver extension

OJD has one DriverKit system extension, `com.openjoystickdriver.VirtualHIDDevice`. It is embedded in the app and has two parts. The virtual HID device factory always runs and needs no controller. The Xbox USB part owns the USB interfaces of genuine Xbox One and Xbox Series controllers. One approval in **System Settings** covers both parts. The Xbox USB part only serves Xbox One and Xbox Series controllers that connect by USB with one of these VID:PID values:

- `045E:02D1`
- `045E:02DD`
- `045E:02E3`
- `045E:02EA`
- `045E:0B00`
- `045E:0B0A`
- `045E:0B12`

Every other controller does not need the Xbox USB part. OJD reads those controllers directly from the app. The Xbox USB part does not publish a virtual controller. The app publishes it.

A build without the `com.apple.developer.driverkit.transport.usb` entitlement has the virtual HID device part only. See [Build options and limits](Building-from-Source.md).

### Approve the extension

Do these steps only if you use one of the controllers above.

1. Open the OJD settings window.
1. Open the **Overview** pane.
1. Find the **Xbox USB Driver** card. It shows **Approval needed** until you approve the extension.
1. Click **Open System Settings**. OJD opens the **Login Items & Extensions** settings.
1. Approve the OpenJoystickDriver extension in **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions**.

When the card shows **Ready**, the extension is active. If the card shows **Needs attention**, click **Repair Xbox USB Driver** when that button appears.

## Further reading

- [Supported controllers](Supported-Controllers.md)
- [Adding or changing a controller record](Controller-Records.md)
- [Controller not detected](Troubleshooting.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Build options and limits](Building-from-Source.md)
- [Overview pane](Using-the-App.md)
- [Security model](Permissions-and-Security.md)
