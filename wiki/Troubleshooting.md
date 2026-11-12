# Troubleshooting

Find solutions for common OpenJoystickDriver (OJD) problems: a controller that is not detected, a game that does not see the controller, and crashes.

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
- [The Home Button Opens Games](#the-home-button-opens-games)
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
2. Open the **Access** area and check **Input Monitoring**. OJD cannot read a controller without it. For more information, see [Permissions](Permissions-and-Security.md).
3. If **Input Monitoring** needs attention, click **Request...**.
4. Allow it in **System Settings**.
5. Click **Restart OpenJoystickDriver**.
6. Reconnect the controller. OJD never reconnects a Bluetooth controller by itself.

### Check the Controller ID

Each connection mode has its own VID:PID. A controller in USB mode and the same controller in Bluetooth mode look like different devices. A dongle has its own ID too.

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](Connecting-Controllers.md).
2. Look for it in [Supported controllers](Supported-Controllers.md).

The built-in catalog has 710 records. A record without a physical test is unverified. An unverified controller may work, may partly work, or may not work.

### Special Cases

- **Xbox One or Xbox Series controller on USB:** These controllers need the [Xbox USB driver](Glossary.md#terms). Check the **Xbox USB Driver** banner below the toolbar of the app window. If it shows **Open System Settings**, click it and approve the driver. If it shows **Repair Xbox USB Driver**, click it. **Xbox USB Driver** in **Settings** > **Advanced** shows the state of the driver. For more information, see [Xbox USB driver](Connecting-Controllers.md).
- **Clone or fake controller:** It may report itself in a way the catalog does not cover. For more information, see [Clone and fake controllers](Supported-Controllers.md).
- **Dongle:** A dongle problem is separate from a controller problem. Test the controller in another connection mode if it has one.
- **The app shows OpenJoystickDriver cannot reach its service:** Run `ojd service start`, then run `ojd status`.
- **SDL sees 0 controllers:** Grant **Input Monitoring** and **Accessibility**, restart OJD, and try again.
- **Xbox USB driver install fails:** Rebuild the signed app, then run `ojd transport-extension activate`.
- **The controller shows Used by another app:** That app reads the controller directly, so OJD cannot. You do not need to do anything for OJD. OJD handles the controller again when the app lets go. The controller detail and `ojd controller list` show the app name.
- **Input stays held, or the status says Needs attention:** Release the controls. Then check the controller input health with `ojd status --json`.

### Check from the Terminal

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
2. Press buttons. If **Input Test** shows no input, see [Controller is not detected](#controller-is-not-detected).
3. In the **Access** area, check **Accessibility**. OJD needs it to publish the [virtual gamepad](Glossary.md#terms).

### Understand Why Apps Differ

OJD publishes a virtual gamepad. Each app reads it with its own API, so an app can read one [virtual gamepad kind](Glossary.md#terms) and not see another. Apps that use SDL, such as Steam, read the `SDLCompatible` virtual gamepad kind. Apps that use the Apple Game Controller framework, such as Safari and **System Settings**, read the `GameControllerCompatible` virtual gamepad kind and do not see `SDLCompatible`.

OJD cannot add SDL to other apps. Each app ships its own SDL version.

These results are not a guarantee.

| App | Result |
| --- | --- |
| Steam | Reads input and rumble of the `SDLCompatible` virtual gamepad kind in a maintainer test |
| CrossOver and Wine | One tester saw no controller with the Xbox [profile](Glossary.md#terms) at `045E:02FD`. Not verified with the `SDLCompatible` virtual gamepad kind at `045E:0B0C` |
| RPCS3 | One tester saw a controller with no input with the Xbox profile at `045E:02FD`. Not verified with the `SDLCompatible` virtual gamepad kind at `045E:0B0C` |
| OpenEmu | One tester saw buttons map to wrong controls with the Xbox profile. Works with the `Generic` virtual gamepad kind |

For each result and its source, see [Game and app compatibility](Playing-Games.md#game-and-app-compatibility).

### Try the Other Virtual Profile

The design of OJD is to pick the virtual gamepad kind by itself. Use this step only to find out whether the virtual gamepad kind is the cause. If another kind fixes a game, report it.

1. In **Controllers**, select the controller.
2. In **Advanced**, find **Virtual gamepad kind**. It appears only for controllers that OJD publishes.
3. Choose **Automatic** or one of the three kinds.
4. Test the game again.

OpenEmu worked with the `Generic` virtual gamepad kind in the same test. Steam with that profile was erratic and slow to respond. The override applies to every controller of that model.

### A Button Does Nothing in Steam

Steam keeps its own mapping for each controller it has seen, and it does not read the mapping that OJD publishes. When Steam's mapping misses a button, Steam ignores that button even though OJD sends it. The maintainer saw this with the `Generic` virtual gamepad kind: Steam's saved mapping had no Guide button, so the PS button of a DualShock 3 did nothing in Steam, while `ojd controller watch` showed `Guide` for each press.

1. Run `ojd controller watch CONTROLLER --output` and press the button. If the line shows the button, OJD sends it.
2. In Steam, open the controller's **Controller Layout** page and choose **Setup Device Inputs**.
3. Press each button when Steam asks for it, including the Guide button.

After that setup, Guide and Select worked in Steam, and Guide opened Big Picture mode. `ojd virtual export-mapping generic` prints the mapping that OJD publishes, so you can compare it with Steam's.

### Try a Different Controller Mode

Some controllers have a Switch Pro mode. In that mode macOS reads the controller itself, and OJD does not publish a virtual gamepad. One tester saw RPCS3, the browser, and **System Settings** work in that mode. HD rumble in that mode drives only the linear haptics. Not verified for other controllers.

For more information, see [Game and app compatibility](Playing-Games.md).

## The Home Button Opens Games

macOS opens the Games app when you press the home button of a controller that it lists in **System Settings** > **Game Controllers**, which includes the OJD virtual gamepad with the `SDLCompatible` virtual gamepad kind.
On a PlayStation controller the home button is the PS button.
To keep the button for your game or for Steam:

1. Open **System Settings** > **Game Controllers**.
2. Under **Home Button**, turn off **Enable Home Button Actions**, or choose another app in **Press Home Button to Open**.

## App Crashes or Does Not Start

This section explains what to do when OJD crashes, does not start, or reports a damaged profile library.

### Collect Information

1. Open the **Activity** area, or run the following command.

   ```shell
   ojd log show --lines 200
   ```

2. Note what you did before the crash.
3. Report it. For more information, see [Reporting a bug](Reporting-a-Bug.md).

OJD clears its log files at each start. Copy the logs before you start OJD again.

### Crash at Every Start

If OJD crashes at every start, two global profiles may be active for one controller model. This is a known issue.

1. Quit OJD.
2. Move `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.plist` to another folder.
3. Open OJD.

### Crash When You Unplug a Controller

Unplugging a USB controller or dongle may crash OJD. Open OJD again. Restart OJD if stale virtual gamepads stay in **System Settings**.

### Damaged Profile Files

OJD reads each profile file in `Profiles/` and the list of active profiles in `ActiveProfiles.plist`. It does not change a file when it finds damage. While damage exists, OJD blocks every change to your profiles until you repair it.

OJD shows two kinds of damage in the **Profiles** area. To repair both from the command line, run `ojd profile recover`.

#### One Damaged Profile

OJD keeps the valid profiles and marks the damaged profile **Needs attention**.

1. Select the damaged profile.
2. Click **Delete Damaged Profile...**.
3. In the alert, click **Delete**.

OJD saves a backup before it changes the file.

#### Damaged Active Profile List

If OJD cannot read `ActiveProfiles.plist`, the area shows **Damaged active profile list**, and no profile is active.

1. Click **Back Up & Reset Active Profiles...**.
2. In the alert, click **Back Up & Reset**.

OJD saves a backup and then writes an empty list. Your profiles are kept, and none of them is active after this step.

#### Find the Backup

Each backup is beside the file it copies: in `~/Library/Application Support/OpenJoystickDriver/Profiles/` for a profile, and in `~/Library/Application Support/OpenJoystickDriver/` for `ActiveProfiles.plist`. The name has the form `FILE.backup-DATE-TIME-ID`. The time is local time.

A backup is a copy of the file as it was before repair. To recover data, open the copy in a text editor. For more information, see [Profile file reference](Profile-File-Reference.md).

## Further Reading

- [Known issues](Known-Issues.md)
- [Frequently asked questions](FAQ.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Connection types](Connecting-Controllers.md)
- [How games see your controller](Playing-Games.md)
- [Importing and exporting profiles](Remapping-Profiles.md)
