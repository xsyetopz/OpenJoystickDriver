# Xbox USB driver extension

This article explains the optional system extension that OpenJoystickDriver (OJD) uses for some Xbox controllers on USB.

The extension is a DriverKit system extension. It only serves Xbox One and Xbox Series controllers that connect by USB with one of these VID:PID values:

- `045E:02D1`
- `045E:02DD`
- `045E:02E3`
- `045E:02EA`
- `045E:0B00`
- `045E:0B0A`
- `045E:0B12`

Every other controller does not need the extension. OJD reads those controllers directly from the app. The extension does not publish a virtual controller. The app publishes it.

## Approve the extension

Do these steps only if you use one of the controllers above.

1. Open the OJD settings window.
1. Open the **Overview** pane.
1. Find the **Xbox USB Driver** card. It shows **Approval needed** until you approve the extension.
1. Click **Open System Settings**. OJD opens the **Login Items & Extensions** settings.
1. Approve the OpenJoystickDriver extension in **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions**.

When the card shows **Ready**, the extension is active. If the card shows **Needs attention**, click **Repair Xbox USB Driver** when that button appears.

## Further reading

- [Overview pane](../using-the-app/overview-pane.md)
- [Security model](../permissions-and-security/security-model.md)
