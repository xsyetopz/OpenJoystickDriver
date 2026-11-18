# Permissions and Security

See which macOS permissions OpenJoystickDriver asks for, why, and how the app protects your Mac.

## Contents

- [Security Model](#security-model)
- [Permissions](#permissions)
- [Further Reading](#further-reading)

## Security Model

OpenJoystickDriver works with System Integrity Protection (SIP) and Apple Mobile File Integrity (AMFI) turned on.

> [!WARNING]
> Never turn off SIP or AMFI for OpenJoystickDriver. No feature needs it.

### Signing

Apple notarized the release app, and the maintainer signed it. Tester builds use a Developer ID signature and are also notarized.

### Xbox USB Driver

The [Xbox USB driver](Glossary.md#terms) reads Xbox One and Xbox Series controllers that you connect with a USB cable. It runs outside the macOS kernel, and macOS asks for your approval first. No other controller uses it. The app shows the [virtual gamepad](Glossary.md#terms) to games. See [Approve the Driver](Connecting-Controllers.md#approve-the-driver).

### Data on Your Mac

- [Profiles](Glossary.md#terms) are in `~/Library/Application Support/OpenJoystickDriver/`. Only your user can read the folder.
- Logs are in `~/Library/Logs/OpenJoystickDriver/`.
- Settings are in the `com.openjoystickdriver` preferences domain.

The only network request is the update check. It contacts GitHub when you click **Check Now**, and at launch if **Check for updates automatically** is on (off by default). The app sends no controller data and doesn't update itself.

### Endpoint Access

The endpoint lets other programs on your Mac read controller input through a local socket. It's off until you click **Turn On** in the **Access** area or run `ojd access enable`. A program needs a grant for each kind of access it uses (`read` or `control`).

A grant names the program's signature, by team ID or as Apple. Programs with an ad-hoc or no signature are refused. `ojd access list` shows programs refused in the last 24 hours.

`ojd access web enable` adds a WebSocket on `127.0.0.1` for overlay pages. Pages use a token from `ojd access grant --token` and can't use `control`. See [access](Command-Reference.md#access).

### Support Report

**Help** > **Copy Support Report** copies a JSON report to the clipboard. The app doesn't save it. It holds service status, virtual gamepad details, permission state, the build version, and your devices' product names. It leaves out serial numbers, file paths, packet data, and location IDs. Read it before you share it.

## Permissions

OpenJoystickDriver asks for a permission only when you ask it to. It requests nothing at launch. A request begins when you do one of these:

- Click **Request...** or **Open System Settings** in the **Access** area.
- Click **Grant Access** in the **Permission needed** banner.
- Run `ojd permission request`.

### Permissions the App Uses

| Permission | What it's for | When you need it |
| --- | --- | --- |
| Input Monitoring | Reads input from a controller | Always |
| Accessibility (Device Control and Data Access on macOS 27) | Shows your controllers to games | Always |
| Keyboard & pointer | Sends keyboard, mouse, and scroll events, including system keys and typed text | When a profile does this |
| Notifications | Shows alerts | Optional |

Open application, open URL, Mission Control, and Run Shortcut need no permission of their own. Which prompts they raise is untested.

The app doesn't use the camera, the microphone, or Full Disk Access. The app uses Bluetooth only to disconnect a wireless controller and to connect a Switch 2 controller. You see no Bluetooth prompt at launch.

### Grant Input Monitoring and Accessibility

- **What:** two switches in macOS System Settings.
- **Why:** with **Input Monitoring**, OJD can read your controller. With **Accessibility**, OJD can hand the controller to games. Without both, games see nothing.
- **When:** once, after you install OJD. Again if a new build asks.
- **Who:** you. macOS lets only you turn these on. OJD can't do it for you.

**Check first.** Open OJD and click **Access** in the sidebar. **Allowed** beside both means you're done.

![The Access area in OJD. A red arrow points to Access in the sidebar. A second arrow points to Allowed, and the box explains Input Monitoring and Accessibility](../docs/screenshots/steps/access-permissions.png)

**Turn them on:**

1. In OJD, click **Grant Access** in the **Permission needed** banner. Or choose Apple menu > **System Settings**, then click **Privacy & Security**.
2. Find the two rows. On macOS 27, **Accessibility** is called **Device Control and Data Access**.

   ![Privacy & Security in System Settings. Red arrows point to Device Control and Data Access and to Input Monitoring](../docs/screenshots/steps/macos-privacy-list.png)

3. Click **Input Monitoring**. Turn on **OpenJoystickDriver**. A blue switch means it's on.

   ![The Input Monitoring page. A red arrow points to the OpenJoystickDriver switch](../docs/screenshots/steps/macos-input-monitoring.png)

4. Click the back arrow. Click **Device Control and Data Access** (**Accessibility** on older macOS). Turn on **OpenJoystickDriver**.

   ![The Device Control and Data Access page. A red arrow points to the OpenJoystickDriver switch](../docs/screenshots/steps/macos-device-control.png)

5. Go back to OJD. If **Restart OpenJoystickDriver** appears in **Access**, click it.

**Check:** **Access** shows **Allowed** twice.

### If OpenJoystickDriver Isn't in the List

macOS remembers its answer for each OJD build. An answer stored for an earlier build can make macOS refuse with no prompt and no list entry.

**Add it by hand:** click **+** under the list, choose **OpenJoystickDriver** in **Applications**, and click **Open**. Then turn on its switch.

**Or clear the stored answers,** then click **Grant Access** again. In Terminal, run:

```sh
tccutil reset ListenEvent com.openjoystickdriver
tccutil reset PostEvent com.openjoystickdriver
tccutil reset Accessibility com.openjoystickdriver
```

### Turn On Notifications

Notifications are optional. They tell you when a controller connects or a profile switches.

1. Choose OpenJoystickDriver > **Settings...**, then turn on a notification switch. Or click **Send Test Notification**.
2. Click **Allow** in the macOS prompt.

If you denied them before, click **Open Notification Settings**. Then turn on **Allow notifications**.

![OpenJoystickDriver in Notifications settings. A red arrow points to the Allow notifications switch](../docs/screenshots/steps/macos-notifications.png)

### Approve the Xbox USB Driver

Only genuine Xbox One and Xbox Series controllers on a USB cable need it. The approval is in **General**, not in **Privacy & Security**. See [Approve the Driver](Connecting-Controllers.md#approve-the-driver).

### Details for Advanced Users

The app holds every permission below. The `ojd` command posts no events.

| Action | Permission it needs | Process that calls the API |
| --- | --- | --- |
| Keyboard, mouse, and scroll events | Post Event access | The app, through `CGEvent.post` |
| System keys (media, volume, brightness, keyboard illumination) | Post Event access | The app, through `CGEvent.post` |
| Type text | Post Event access | The app, through `CGEvent.post`. The action fails with a named error while secure input is on (`IsSecureEventInputEnabled`) |
| Open application, open URL, Mission Control | None of its own | The app, through `NSWorkspace` |
| Run Shortcut | None of its own | The app starts `/usr/bin/shortcuts run NAME` as a child process. The Shortcuts tool does the work |
| MIDI output | None of its own | The app creates one virtual CoreMIDI source |
| Speak | None of its own | The app, through `AVSpeechSynthesizer` |

Post Event access is the macOS name for **Keyboard & pointer**. Without it, the action fails and posts nothing. `ojd permission list` reads the service's permissions when it runs, and its own when it doesn't.

Untested on hardware: whether macOS attributes a `shortcuts` process's permission to the app, and whether **Keyboard & pointer** and **Accessibility** share one switch.

## Further Reading

- [Access Area](Using-the-App.md#access-area)
- [Game Does Not See the controller](Troubleshooting.md#game-does-not-see-the-controller)
- [Reporting a Bug](Reporting-a-Bug.md)
- [Updating and Uninstalling](Updating-and-Uninstalling.md)
