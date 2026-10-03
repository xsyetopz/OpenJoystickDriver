# Using the app

Learn the menu-bar item, the app window, and the tools in each pane.

## Contents

- [Menu-bar item](#menu-bar-item)
- [Overview pane](#overview-pane)
- [Controllers pane](#controllers-pane)
- [Console and settings](#console-and-settings)
- [Testing a controller](#testing-a-controller)
- [Further reading](#further-reading)

## Menu-bar item

The menu-bar item shows OpenJoystickDriver status and opens the app window.

### About the icon

OJD has no Dock icon. The app runs from the menu bar. The icon does not change with status. To read status, open the menu. Click the icon to open it.

### Menu items

The menu contains these items, from top to bottom:

- A summary row that you cannot click. It shows readiness, the number of controllers, and the active profile, for example `Ready · 1 controller connected · My controller`. If no profile is active, it shows **No active profile**.
- **Request Access...** appears only when a permission is missing. It starts the macOS permission requests and opens the matching **System Settings** pane.
- **Controllers** lists each connected controller. **No controller connected** appears when the list is empty.
- **Show OpenJoystickDriver** opens the app window on the last pane you used.
- **Settings...** (<kbd>Command</kbd>+<kbd>,</kbd>) opens the **Settings** pane.
- **Help** contains **Open Console...** and **GitHub**.
- **About OpenJoystickDriver** shows the version.
- **Quit OpenJoystickDriver** (<kbd>Command</kbd>+<kbd>Q</kbd>) stops OJD.

### Controller entries

Each controller in the **Controllers** submenu has its own submenu:

- **Controllers...** opens the **Controllers** pane.
- **Disconnect Wireless Controller...** appears only for Bluetooth controllers. OJD shows a **Disconnect Wireless Controller?** alert to confirm. The controller stays disconnected until you connect it again by hand.

### Quit and reopen

Quit stops the runtime. OJD does not start again by itself. Start it from the Applications folder. Opening the app again while it runs shows the window on the **Overview** pane. Closing the window with the red button only hides it.

## Overview pane

The **Overview** pane shows the Xbox USB driver state, the access that OpenJoystickDriver has, and the overall status.

### Open the pane

The app window has a sidebar with these panes: **Overview**, **Controllers**, **Profiles**, **Console**, **Developer Tools**, and **Settings**. **Developer Tools** appears only when you turn it on in **Settings**. Click the sidebar button in the toolbar to hide or show the sidebar.

### Xbox USB Driver card

This card is about the OJD driver extension. Only some Xbox One and Xbox Series controllers on USB need its Xbox USB part. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

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
- **Copy Support Report** copies a report to the clipboard. No message tells you that the copy worked. For more information, see [Reporting a bug](Reporting-a-Bug.md).
- **Uninstall** appears when the driver is active. It asks you to approve and then deactivates the driver.

### Access & readiness

Four cards show **Input Monitoring**, **Accessibility**, **Keyboard & pointer**, and **Notifications**. Each card shows one value:

- **Allowed**
- **Needs attention**
- **Checking...**
- **Not needed** (only for **Keyboard & pointer**)
- **Unavailable**
- **Not requested**, **Banners off**, or **Sound off** (only for **Notifications**)

Click **Request...** on a card to ask for that access. If **Input Monitoring** or **Accessibility** is not allowed, **Restart OpenJoystickDriver** appears. For more information, see [Permissions](Permissions-and-Security.md#permissions).

### Status card

The status card shows one status, such as **Ready**, **Connect a controller**, **Needs attention**, or **Starting...**. **Needs attention** also appears when a connected controller stops sending input. Click **Refresh** to read the status again.

## Controllers pane

The **Controllers** pane lists connected controllers and shows details and actions for the selected controller.

### The list

The list shows each connected controller. Click **Refresh controllers** to read the list again. If no controller appears, the pane shows **No controller connected**. For more information, see [Controller not detected](Troubleshooting.md).

### Controller details

Select a controller to see its details. The details include these fields when the controller reports them:

- **Published as**: the virtual controller identity that OJD shows to games. A controller that macOS handles itself shows **Native macOS gamepad, not published**.
- **Protocol**
- **Serial number**
- **Battery**, **Charging state**, and **Cable state**
- **USB VID/PID**: the vendor and product IDs. For more information, see [Finding your controller ID](Connecting-Controllers.md).
- **Input endpoint** and **Output endpoint**
- **Active profile**

A field that the controller does not report shows **Not reported**.

### Actions

- **Open Input Test...** opens the test window. For more information, see [Testing a controller](Testing-a-Controller.md).
- **Disconnect from OpenJoystickDriver** pauses input, physical effects, and virtual output for this controller. The controller then shows **Suspended**. Click **Resume** to continue. **Open Input Test...** is off while the controller shows **Suspended**.
- **Disconnect Wireless Controller...** appears only for Bluetooth controllers. It closes the Bluetooth link. The controller stays disconnected until you connect it again by hand. OJD never reconnects Bluetooth by itself.

### Advanced section

The **Advanced** section appears for controllers that macOS does not handle itself. It contains the **Virtual HID profile** menu:

- **Automatic** lets OJD choose the virtual controller profile.
- **Xbox Wireless Controller (hid-xbox-one-s-bt)** forces the Xbox profile.
- **OpenJoystickDriver Generic HID Gamepad (hid-generic)** forces the generic profile.

The **Live profile** row shows the profile in use and its source: **Automatic**, **Override**, or **Automatic, override rejected**.

> [!NOTE]
> The override applies to every connected controller of the same model, because OJD stores it per VID:PID.

The change takes effect at once. **Updating virtual HID profile...** shows while it applies. If activation fails, OJD restores the previous profile and shows a message. For more information, see [How games see your controller](Playing-Games.md).

## Console and settings

The **Console** pane shows OpenJoystickDriver logs. The **Settings** pane controls login, notifications, updates, and developer tools.

### Console pane

Open **Console** from the sidebar or from **Help** > **Open Console...** in the menu-bar menu.

- **Stream** selects **All**, **Output**, or **Errors**.
- **Refresh** reads the logs again.
- **Copy All** copies the shown lines.

If there are no lines, the pane shows **No log entries.** Each start of OJD clears the logs. For more information, see [Reporting a bug](Reporting-a-Bug.md).

### Settings pane

Open **Settings** from the sidebar or press <kbd>Command</kbd>+<kbd>,</kbd>.

#### General

**Start at login** opens OJD in the menu bar when you log in. It needs macOS 13 or later. If macOS needs approval, allow OJD in **System Settings** > **General** > **Login Items**.

> [!NOTE]
> The **Start at login** switch removes the login item but does not record that you opted out. At the next start, OJD registers itself again. This is what the source code does. It is not verified on a running system. To stay opted out, run the `app login disable` command. For more information, see [Command reference](Command-Reference.md).

#### Notifications

Turn notifications on for these events:

- **Controllers**: **Connected** and **Disconnected**.
- **Profiles**: **Activated or switched** and **Deactivated**.
- **Play a sound**.

Click **Send Test Notification** to test delivery. If macOS denies notifications, OJD turns the toggles off. Click **Open Notification Settings** to fix this.

#### Updates

Click **Check Now** to look for a newer version. OJD contacts GitHub only when you click it. The result is **Up to date**, **Update available**, or **Update check failed**. Click **View Update** to open the release page. OJD does not download or install anything. Select **Include prerelease updates** to include beta versions.

#### Developer Tools

Select **Enable Developer Tools** to add the **Developer Tools** pane. It shows controller input and USB packet tools. For more information, see [Finding your controller ID](Connecting-Controllers.md).

## Testing a controller

The Input Test window shows live input, rumble, and lighting. For more information, see [Testing a controller](Testing-a-Controller.md).

## Further reading

- [Testing a controller](Testing-a-Controller.md)
- [Permissions](Permissions-and-Security.md#permissions)
- [Controller not detected](Troubleshooting.md)
- [Connection types](Connecting-Controllers.md)
- [Known issues](Known-Issues.md)
- [Updating OpenJoystickDriver](Updating-and-Uninstalling.md)
