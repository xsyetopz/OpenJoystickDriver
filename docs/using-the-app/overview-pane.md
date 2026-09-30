# Overview pane

The **Overview** pane shows the Xbox USB driver state, the access that OpenJoystickDriver has, and the overall status.

## Open the pane

The app window has a sidebar with these panes: **Overview**, **Controllers**, **Profiles**, **Console**, **Developer Tools**, and **Settings**. **Developer Tools** appears only when you turn it on in **Settings**. Click the sidebar button in the toolbar to hide or show the sidebar.

## Xbox USB Driver card

This card is about the optional system extension. Only some Xbox One and Xbox Series controllers on USB need it. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

| Badge | Meaning |
| --- | --- |
| Checking... | OJD reads the driver state. |
| Activating... | The driver needs activation or replacement. OJD submits a request. |
| Approval needed | macOS waits for your approval. |
| Ready | OJD installed the driver and it runs. |
| Needs attention | The driver is missing, invalid, or failed. |

The card has these buttons:

- **Refresh** reads the state again.
- **Open System Settings** appears when macOS waits for approval.
- **Repair Xbox USB Driver** appears when the driver needs activation, failed, or is invalid.
- **Controller Test** opens the **Controllers** pane.
- **Copy Support Report** copies a report to the clipboard. No message tells you that the copy worked. For more information, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).
- **Uninstall** appears when the driver is active. It asks you to approve and then deactivates the driver.

## Access & readiness

Four cards show **Input Monitoring**, **Accessibility**, **Keyboard & pointer**, and **Notifications**. Each card shows one value:

- **Allowed**
- **Needs attention**
- **Checking...**
- **Not needed** (only for **Keyboard & pointer**)
- **Unavailable**
- **Not requested**, **Banners off**, or **Sound off** (only for **Notifications**)

Click **Request...** on a card to ask for that access. If **Input Monitoring** or **Accessibility** is not allowed, **Restart OpenJoystickDriver** appears. For more information, see [Permissions](../permissions-and-security/permissions.md).

## Status card

The status card shows one status, such as **Ready**, **Connect a controller**, **Needs attention**, or **Starting...**. **Needs attention** also appears when a connected controller stops sending input. Click **Refresh** to read the status again.

## Further reading

- [Menu-bar item](menu-bar-item.md)
- [Controllers pane](controllers-pane.md)
- [Controller not detected](../troubleshooting/controller-not-detected.md)
