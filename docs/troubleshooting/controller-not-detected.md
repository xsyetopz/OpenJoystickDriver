# Controller is not detected

This article explains what to check when OpenJoystickDriver (OJD) does not list your controller or shows no input.

## Check the basics

1. Make sure OJD runs. Look for the menu bar item.
1. Open **Overview** and check **Input Monitoring**. OJD cannot read a controller without it. For more information, see [Permissions](../permissions-and-security/permissions.md).
1. If **Input Monitoring** needs attention, click **Request...**.
1. Allow it in **System Settings**.
1. Click **Restart OpenJoystickDriver**.
1. Reconnect the controller. OJD never reconnects a Bluetooth controller by itself.

## Check the controller ID

Each connection mode has its own VID:PID. A controller in USB mode and the same controller in Bluetooth mode look like different devices. A dongle has its own ID too.

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).
1. Look for it in [Supported controllers](../connecting-controllers/supported-controllers.md).

The built-in catalog has 696 records. A record without a physical test is unverified. An unverified controller may work, may partly work, or may not work.

## Special cases

- **Xbox One or Xbox Series controller on USB:** These controllers need the Xbox USB system extension. In **Overview**, check the **Xbox USB Driver** card. If it shows **Approval needed**, click **Open System Settings** and approve it. If it shows **Needs attention**, click **Repair Xbox USB Driver**. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).
- **Clone or fake controller:** It may report itself in a way the catalog does not cover. For more information, see [Clone and fake controllers](../connecting-controllers/clone-and-fake-controllers.md).
- **Dongle:** A dongle problem is separate from a controller problem. Test the controller in another connection mode if it has one.

## Check from the terminal

Run the following command to see the runtime state.

```shell
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
```

If the controller is still missing, report it. For more information, see [Reporting a bug](reporting-a-bug.md).

## Further reading

- [Connection types](../connecting-controllers/connection-types.md)
- [Known issues](known-issues.md)
