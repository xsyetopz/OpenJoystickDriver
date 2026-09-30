# Finding your controller ID

This article explains how to read the VID:PID of your controller.

The VID:PID is the vendor ID and product ID that identify one controller model. A report without a VID:PID is hard to use. Each connection mode has its own VID:PID. For more information, see [Connection types](connection-types.md).

## Read the ID for a USB controller

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

## Read the ID for any connection

Use this method for a Bluetooth controller. Bluetooth controllers do not appear in the USB list.

1. Open the OJD settings window.
1. Open **Settings**.
1. Turn on **Enable Developer Tools**.
1. Open the **Developer Tools** pane.
1. Select your controller.

The pane shows the controller details, including its USB ID, connection type, and endpoints.

## Further reading

- [Supported controllers](supported-controllers.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
