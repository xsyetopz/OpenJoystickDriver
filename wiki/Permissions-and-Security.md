# Permissions and Security

Learn which macOS permissions OpenJoystickDriver needs and how it protects your Mac.

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

The OJD driver extension, `com.openjoystickdriver.XboxUSBDevice`, is a DriverKit system extension. It runs in user space, not in the kernel. macOS asks for your approval before it starts. OJD uses it only for Xbox One and Xbox Series controllers on USB. The virtual controller comes from the app, not from the extension. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

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

- Click **Request...** on a permission row in the **Access** area.
- Click **Grant Access** in the menu-bar menu.
- Run the `permissions request` command.

OJD reads the permission state every second. A request result is not treated as a grant. OJD reads the real state again.

### Permission List

| Permission | Purpose | Needed |
| --- | --- | --- |
| Input Monitoring | Read reports from a physical controller | Always |
| Accessibility | Publish the virtual controller | Always |
| Keyboard & pointer | Send keyboard, mouse, or scroll events from a profile, including system keys and typed text | Only when a profile does so |
| Notifications | Show notifications | Optional |

Open application, open URL, Mission Control, and Run Shortcut need no permission of their own. The Shortcuts app may ask its own questions. OJD does not use private macOS interfaces for system actions: DisplayServices, CoreDock, SkyLight, CGS, and MediaRemote are out of scope. Not checked on hardware: which prompts these actions raise.

### Which Process Holds Each Permission

macOS ties a permission to the process that calls the API. The OpenJoystickDriver service runs inside the app, so the app holds every permission in this table. The `ojd` command sends requests to the service and posts no events of its own.
| Action | Permission it needs | Process that calls the API |
| --- | --- | --- |
| Keyboard, mouse, and scroll events | Post Event access | The app, through `CGEvent.post` |
| System keys (media, volume, brightness, keyboard illumination) | Post Event access | The app, through `CGEvent.post` |
| Type text | Post Event access | The app, through `CGEvent.post`. The action fails with a named error while secure input is on (`IsSecureEventInputEnabled`) |
| Open application, open URL, Mission Control | None of its own | The app, through `NSWorkspace` |
| Run Shortcut | None of its own | The app starts `/usr/bin/shortcuts run NAME` as a child process. The Shortcuts tool does the work |
| MIDI output | None of its own | The app creates one virtual CoreMIDI source |
| Speak | None of its own | The app, through `AVSpeechSynthesizer` |

Before the app posts an event, it checks Post Event access. If the permission is missing, the action fails with a named error and posts nothing. No action sends an Apple Event, so no action in this table needs Automation access. `ojd permission` reads the permission from the service when the service runs, and from the `ojd` process when it does not. Not checked on hardware: which prompts these actions raise, and whether macOS attributes the permission of a `shortcuts` child process to the app.

Not verified on hardware: the **Keyboard & pointer** row and the **Accessibility** row may use the same switch in **System Settings**.

OJD does not use camera, microphone, or Full Disk Access permissions. It reads Bluetooth controllers as HID devices, so they need **Input Monitoring**. OJD uses Bluetooth only to disconnect a wireless controller. Whether macOS asks for Bluetooth permission for this is not verified.

### Grant Input Monitoring and Accessibility

1. Open the **Access** area, or click the menu-bar icon.
2. Click **Request...** on the **Input Monitoring** row, or click **Grant Access** in the menu.
3. Allow **OpenJoystickDriver** in **System Settings** > **Privacy & Security** > **Input Monitoring**.
4. Repeat for **System Settings** > **Privacy & Security** > **Accessibility**.
5. Click **Restart OpenJoystickDriver** in the **Access** area if it appears.

Without **Input Monitoring**, Input Test shows **Input Monitoring permission required**. Without **Accessibility**, the virtual controller does not work.

### Grant Notifications

1. Open **Settings** and turn on a notification toggle, or click **Send Test Notification**.
2. Allow the macOS prompt.

If you denied notifications before, click **Open Notification Settings**. The **Notifications** row in the **Access** area shows **Banners off** or **Sound off** when macOS turns those parts off.

### Xbox USB Driver Approval

The OJD driver extension needs approval, but it is not a privacy permission. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).

## Further Reading

- [Access area](Using-the-App.md#access-area)
- [Controller not detected](Troubleshooting.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Uninstalling OpenJoystickDriver](Updating-and-Uninstalling.md)
