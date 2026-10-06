# Troubleshooting

Find solutions for common OpenJoystickDriver (OJD) problems: a controller that is not detected, a game that does not see the controller, and crashes.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [Controller Is Not Detected](#controller-is-not-detected)
  - [Check the Basics](#check-the-basics)
  - [Check the Controller ID](#check-the-controller-id)
  - [Special Cases](#special-cases)
  - [Check From the Terminal](#check-from-the-terminal)
- [Game Does Not See the Controller](#game-does-not-see-the-controller)
  - [Check OJD First](#check-ojd-first)
  - [Understand Why Apps Differ](#understand-why-apps-differ)
  - [Try the Other Virtual Profile](#try-the-other-virtual-profile)
  - [Try a Different Controller Mode](#try-a-different-controller-mode)
- [App Crashes Or Does Not Start](#app-crashes-or-does-not-start)
  - [Collect Information](#collect-information)
  - [Crash At Every Start](#crash-at-every-start)
  - [Crash When You Unplug a Controller](#crash-when-you-unplug-a-controller)
  - [Damaged Profile Files](#damaged-profile-files)
- [Further Reading](#further-reading)

## Controller Is Not Detected

This section explains what to check when OJD does not list your controller or shows no input.

### Check the Basics

1. Make sure OJD runs. Look for the menu bar item.
1. Open **Overview** and check **Input Monitoring**. OJD cannot read a controller without it. For more information, see [Permissions](Permissions-and-Security.md).
1. If **Input Monitoring** needs attention, click **Request...**.
1. Allow it in **System Settings**.
1. Click **Restart OpenJoystickDriver**.
1. Reconnect the controller. OJD never reconnects a Bluetooth controller by itself.

### Check the Controller ID

Each connection mode has its own VID:PID. A controller in USB mode and the same controller in Bluetooth mode look like different devices. A dongle has its own ID too.

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](Connecting-Controllers.md).
1. Look for it in [Supported controllers](Supported-Controllers.md).

The built-in catalog has 696 records. A record without a physical test is unverified. An unverified controller may work, may partly work, or may not work.

### Special Cases

- **Xbox One or Xbox Series controller on USB:** These controllers need the OJD driver extension. In **Overview**, check the **Xbox USB Driver** card. If it shows **Approval needed**, click **Open System Settings** and approve it. If it shows **Needs attention**, click **Repair Xbox USB Driver**. For more information, see [Xbox USB driver extension](Connecting-Controllers.md).
- **Clone or fake controller:** It may report itself in a way the catalog does not cover. For more information, see [Clone and fake controllers](Supported-Controllers.md).
- **Dongle:** A dongle problem is separate from a controller problem. Test the controller in another connection mode if it has one.
- **Runtime disconnected:** Run `ojd service start`, then run `ojd status`.
- **SDL sees 0 controllers:** Grant **Input Monitoring** and **Accessibility**, restart OJD, and try again.
- **Xbox USB driver extension install fails:** Rebuild the signed app, then run `ojd extension activate`.
- **Input stays held, or the status says Needs attention:** Release the controls. Then check the controller input health with `ojd status --json`.

### Check From the Terminal

Run the following command to see the runtime state.

```shell
ojd status
```

For more information about `ojd`, see [Using the command line](Command-Line.md).

If the controller is still missing, report it. For more information, see [Reporting a bug](Reporting-a-Bug.md).

## Game Does Not See the Controller

This section explains what to check when a controller works in OJD but not in a game or app.

### Check OJD First

1. Open the **Input Test** window for the controller. For more information, see [Testing a controller](Testing-a-Controller.md).
1. Press buttons. If **Input Test** shows no input, see [Controller is not detected](#controller-is-not-detected).
1. In **Overview**, check **Accessibility**. OJD needs it to publish the virtual controller.

### Understand Why Apps Differ

OJD publishes a virtual controller. Each app reads it with its own API. One tester saw apps that use the Apple Game Controller framework, the browser Gamepad API, or **System Settings** read it. The maintainer did not check this. Apps that use SDL may not read it.

OJD cannot add SDL to other apps. Each app ships its own SDL version.

One tester saw these results with the Xbox virtual profile. This is not a guarantee.

| App | Result |
| --- | --- |
| Steam | Shows a phantom controller with no input |
| CrossOver and Wine | No controller |
| RPCS3 | Sees a controller, no input |
| OpenEmu | Buttons map to wrong controls |

### Try the Other Virtual Profile

The design of OJD is to pick the virtual profile by itself. Use this step only to find out whether the profile is the cause. If a profile fixes a game, report it.

1. In **Controllers**, select the controller.
1. In **Advanced**, find **Virtual HID profile**. It appears only for controllers that OJD publishes.
1. Choose **Automatic** or one of the two profiles.
1. Test the game again.

OpenEmu worked with the `hid-generic` profile in the same test. Steam with that profile was erratic and slow to respond. The override applies to every controller of that model.

### Try a Different Controller Mode

Some controllers have a Switch Pro mode. In that mode macOS reads the controller itself, and OJD does not publish a virtual controller. One tester saw RPCS3, the browser, and **System Settings** work in that mode. HD rumble in that mode drives only the linear haptics. Not verified for other controllers.

For more information, see [Game and app compatibility](Playing-Games.md).

## App Crashes Or Does Not Start

This section explains what to do when OJD crashes, does not start, or reports a damaged profile library.

### Collect Information

1. Open the Console pane, or run the following command.

   ```shell
   ojd log show --lines 200
   ```

1. Note what you did before the crash.
1. Report it. For more information, see [Reporting a bug](Reporting-a-Bug.md).

OJD clears its log files at each start. Copy the logs before you start OJD again.

### Crash At Every Start

If OJD crashes at every start, two global profiles may be active for one controller model. This is a known issue.

1. Quit OJD.
1. Move `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.json` to another folder.
1. Open OJD.

### Crash When You Unplug a Controller

Unplugging a USB controller or dongle may crash OJD. Open OJD again. Restart OJD if stale virtual controllers stay in **System Settings**.

### Damaged Profile Files

OJD reads each profile file in `Profiles/` and the list of active profiles in `ActiveProfiles.json`. It does not change a file when it finds damage. While damage exists, OJD blocks every change to your profiles until you repair it.

OJD shows two kinds of damage in the **Profiles** pane. To repair both from the command line, run `ojd profile recover`.

#### One Damaged Profile

OJD keeps the valid profiles and marks the damaged profile **Needs attention**.

1. Select the damaged profile.
1. Click **Delete Damaged Profile...**.
1. In the alert, click **Delete**.

OJD saves a backup before it changes the file.

#### Damaged Active Profile List

If OJD cannot read `ActiveProfiles.json`, the pane shows **Damaged active profile list**, and no profile is active.

1. Click **Back Up & Reset Active Profiles...**.
1. In the alert, click **Back Up & Reset**.

OJD saves a backup and then writes an empty list. Your profiles are kept, and none of them is active after this step.

#### Find the Backup

Each backup is beside the file it copies: in `~/Library/Application Support/OpenJoystickDriver/Profiles/` for a profile, and in `~/Library/Application Support/OpenJoystickDriver/` for `ActiveProfiles.json`. The name has the form `FILE.backup-DATE-TIME-ID`. The time is local time.

A backup is a copy of the file as it was before repair. To recover data, open the copy in a text editor. For more information, see [Profile file reference](Profile-File-Reference.md).

## Further Reading

- [Known issues](Known-Issues.md)
- [Frequently asked questions](FAQ.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Connection types](Connecting-Controllers.md)
- [How games see your controller](Playing-Games.md)
- [Importing and exporting profiles](Remapping-Profiles.md)
