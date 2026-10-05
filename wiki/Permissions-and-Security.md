# Permissions and Security

Learn which macOS permissions OpenJoystickDriver needs and how it protects your Mac.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [Security Model](#security-model)
- [Permissions](#permissions)
- [Further Reading](#further-reading)

## Security Model

OpenJoystickDriver works with System Integrity Protection (SIP) and Apple Mobile File Integrity (AMFI) turned on.

> [!WARNING]
> Never turn off SIP or AMFI for OJD. No OJD feature needs it. If a guide says to do so, do not follow it.

### Signing

Apple notarized the release app, and the maintainer signed it. Tester builds use a Developer ID signature and are also notarized.

### System Extension

The OJD driver extension, `com.openjoystickdriver.VirtualHIDDevice`, is a DriverKit system extension. It runs in user space, not in the kernel. macOS asks for your approval before it starts. One approval covers both of its parts: the virtual HID device factory, and the Xbox USB part that OJD uses only for Xbox One and Xbox Series controllers on USB. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

### Data On Your Mac

OJD stores this data locally:

- Profiles in `~/Library/Application Support/OpenJoystickDriver/`. Only your user can read the folder.
- Logs in `~/Library/Logs/OpenJoystickDriver/`. Each start of OJD clears them.
- Settings in the `com.openjoystickdriver` preferences domain.

The only network request in the OJD source is the update check. It runs when you click **Check Now** and contacts GitHub. OJD does not send controller data. OJD has no automatic update.

### Endpoint Access

The endpoint is a local socket that other programs can read controller input from. It is off until you run `ojd access enable`. Only programs that you grant with `ojd access grant` can use it, and a program needs a grant for each scope that it uses. The service reads the signature of each program that connects from the kernel, not from the program. A grant names that signature, by team ID or as Apple, so OJD refuses ad-hoc signed and unsigned programs. The grants are in `~/Library/Application Support/OpenJoystickDriver/AccessGrants.json`. Until the service stops, the endpoint remembers the programs that it refused in the last 24 hours, so that you can see them with `ojd access list`. For the commands, see [access](Command-Reference.md#access).

### Support Report

**Copy Support Report** copies a JSON report to the clipboard. OJD does not save it to disk. The report contains service status, virtual device details, Input Monitoring state, build identity, and Apple game controller data. It contains product names of your devices. By its own privacy flags, it leaves out serial numbers, file paths, packet data, and HID location IDs. Read the report before you share it.

## Permissions

OpenJoystickDriver asks for macOS permissions only when you request them, and each permission has one purpose.

### When OJD Asks

OJD requests nothing at start. A request starts only when you do one of these actions:

- Click **Request...** on a card in the **Overview** pane.
- Click **Request Access...** in the menu-bar menu.
- Run the `permissions request` command.

OJD reads the permission state every second. A request result is not treated as a grant. OJD reads the real state again.

### Permission List

| Permission | Purpose | Needed |
| --- | --- | --- |
| Input Monitoring | Read reports from a physical controller | Always |
| Accessibility | Publish the virtual controller | Always |
| Keyboard & pointer | Send keyboard, mouse, or scroll events from a profile | Only when a profile does so |
| Notifications | Show notifications | Optional |

Not verified on hardware: the **Keyboard & pointer** card and the **Accessibility** card may use the same switch in **System Settings**.

OJD does not use camera, microphone, or Full Disk Access permissions. It reads Bluetooth controllers as HID devices, so they need **Input Monitoring**. OJD uses Bluetooth only to disconnect a wireless controller. Whether macOS asks for Bluetooth permission for this is not verified.

### Grant Input Monitoring and Accessibility

1. Open the **Overview** pane, or click the menu-bar icon.
1. Click **Request...** on the **Input Monitoring** card, or click **Request Access...** in the menu.
1. Allow **OpenJoystickDriver** in **System Settings** > **Privacy & Security** > **Input Monitoring**.
1. Repeat for **System Settings** > **Privacy & Security** > **Accessibility**.
1. Click **Restart OpenJoystickDriver** on the **Overview** pane if it appears.

Without **Input Monitoring**, Input Test shows **Input Monitoring permission required**. Without **Accessibility**, the virtual controller does not work.

### Grant Notifications

1. Open **Settings** and turn on a notification toggle, or click **Send Test Notification**.
1. Allow the macOS prompt.

If you denied notifications before, click **Open Notification Settings**. The **Notifications** card shows **Banners off** or **Sound off** when macOS turns those parts off.

### Xbox USB Driver Approval

The OJD driver extension needs approval, but it is not a privacy permission. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

## Further Reading

- [Overview pane](Using-the-App.md#overview-pane)
- [Controller not detected](Troubleshooting.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Uninstalling OpenJoystickDriver](Updating-and-Uninstalling.md)
