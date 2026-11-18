# Troubleshooting

Fix common OpenJoystickDriver (OJD) problems: an undetected controller, a game that misses the controller, and crashes.

## Contents

- [If a Controller Isn't Detected](#if-a-controller-isnt-detected)
  - [Check the Basics](#check-the-basics)
  - [Check the Controller ID](#check-the-controller-id)
  - [Special Cases](#special-cases)
  - [Check from the Terminal](#check-from-the-terminal)
- [Game Does Not See the Controller](#game-does-not-see-the-controller)
  - [Check OJD First](#check-ojd-first)
  - [Understand Why Apps Differ](#understand-why-apps-differ)
  - [Try a Different Kind](#try-a-different-kind)
  - [If a Button Does Nothing in Steam](#if-a-button-does-nothing-in-steam)
  - [Try a Different Controller Mode](#try-a-different-controller-mode)
- [If the Home Button Opens Games](#if-the-home-button-opens-games)
- [App Crashes or Does Not Start](#app-crashes-or-does-not-start)
  - [Collect Information](#collect-information)
  - [Crash When You Unplug a Controller](#crash-when-you-unplug-a-controller)
  - [Damaged Profile Files](#damaged-profile-files)
- [Further Reading](#further-reading)

## If a Controller Isn't Detected

### Check the Basics

1. Make sure OJD runs. Look for its icon in the menu bar.
2. Click **Access** in the sidebar and check **Input Monitoring**. OJD can't read a controller without it. See [Permissions](Permissions-and-Security.md).
3. If it needs attention, click **Request...** and allow it in **System Settings**.
4. Click **Restart OpenJoystickDriver**.
5. Reconnect the controller. OJD never reconnects Bluetooth controllers.

### Check the Controller ID

Each [connection](Glossary.md#terms) has its own ID. A controller over USB and over Bluetooth looks like two devices, and a dongle has its own ID.

1. Find your controller's ID. See [Finding Your Controller ID](Connecting-Controllers.md#finding-your-controller-id).
2. Look for it in [Supported Controllers](Supported-Controllers.md).

### Special Cases

- An Xbox One or Xbox Series controller on USB needs the [Xbox USB driver](Glossary.md#terms). If the banner below the toolbar shows **Open System Settings** or **Repair Xbox USB Driver**, click it. See [Xbox USB Driver](Connecting-Controllers.md#xbox-usb-driver).
- If the driver doesn't install, run `ojd transport-extension activate`.
- A clone or fake controller may not match OJD's list. See [Clone and Fake Controllers](Supported-Controllers.md#clone-and-fake-controllers).
- With a dongle, the problem may be the dongle. Try another controller mode.
- If the app shows **OpenJoystickDriver cannot reach its service**, run `ojd service start`, then `ojd status`.
- If SDL games see no controllers, allow **Input Monitoring** and **Accessibility**, then reopen OJD. This fix is untested.
- If `ojd status` or the Controllers page lists the controller as unserved with "Used by" and an app name, that app has it, and `ojd controller list` leaves it out. OJD takes it back when the app lets go.
- If a control seems stuck, or the status shows **Needs attention**, let go of all controls, then run `ojd status --json`.

### Check from the Terminal

Run:

```shell
ojd status
```

See [Using the Command Line](Command-Line.md). If the controller is still missing, see [Reporting a Bug](Reporting-a-Bug.md).

## Game Does Not See the Controller

### Check OJD First

1. Open **Input Test** for the controller. See [Testing a Controller](Testing-a-Controller.md).
2. Press buttons. If it shows no input, see [If a Controller Isn't Detected](#if-a-controller-isnt-detected).
3. Click **Access** in the sidebar and check **Accessibility**, which OJD needs for the [virtual gamepad](Glossary.md#terms).

### Understand Why Apps Differ

An app can see one virtual gamepad [kind](Glossary.md#terms) and miss another. Apps that use SDL, such as Steam, read the default (Xbox-style) kind. Apps that use Apple's Game Controller framework, such as Safari and **System Settings**, read only the Game Controller kind.

Results are in [Game and App Compatibility](Playing-Games.md#game-and-app-compatibility). None is a guarantee.

### Try a Different Kind

This tests whether the kind causes the problem. If another kind fixes a game, report it.

1. Click **Controllers** in the sidebar, then select the controller.
2. Expand **Advanced** and find **Virtual gamepad kind**.
3. Choose **Automatic** or one of the three kinds.
4. Test the game again.

The override applies to every controller of that model. Steam with the Generic kind was erratic and slow.

### If a Button Does Nothing in Steam

Steam keeps its own mapping for each controller. If it misses a button, Steam ignores it even though OJD sends it. The maintainer saw this with the Guide button of a DualShock 3.

1. Run `ojd controller watch CONTROLLER --output` and press the button. If the line shows it, OJD sends it.
2. In Steam, open **Controller Layout** for the controller and choose **Setup Device Inputs**.
3. Press each button when Steam asks, including Guide.

After this, Guide and Select worked. To compare Steam's mapping with OJD's, run `ojd virtual export-mapping generic`.

### Try a Different Controller Mode

Some controllers have a Switch Pro mode. macOS then reads the controller itself, and OJD publishes no virtual gamepad. One tester saw RPCS3, the browser, and **System Settings** work. It is untested for other controllers.

## If the Home Button Opens Games

macOS opens the Games app when you press the home button of a controller listed in **System Settings** > **Game Controllers**. On a PlayStation controller, that is the PS button. To keep the button for your game:

1. Open **System Settings** > **Game Controllers**.
2. Under **Home Button**, turn off **Enable Home Button Actions**, or choose another app in **Press Home Button to Open**.

## App Crashes or Does Not Start

### Collect Information

1. Click **Activity** in the sidebar, or run:

   ```shell
   ojd log show --lines 200
   ```

2. Note what you did before the crash.
3. Report it. See [Reporting a Bug](Reporting-a-Bug.md).

Copy the logs before you open OJD again.

### Crash When You Unplug a Controller

Unplugging a USB controller or dongle may crash OJD, but not every time. OJD keeps each controller's macOS plug-in loaded to prevent it; whether that works is unconfirmed. Open OJD again. If stale virtual gamepads stay in **System Settings**, restart OJD. See [Known Issues](Known-Issues.md#unplugging-a-usb-controller-can-crash-the-app).

### Damaged Profile Files

Until you repair damage to a profile file or `ActiveProfiles.plist`, OJD blocks every profile change. To repair both kinds from Terminal, run `ojd profile recover`.

#### Repair One Damaged Profile

OJD keeps the valid profiles and marks the damaged one **Needs attention**.

1. Select the damaged profile.
2. Click **Delete Damaged Profile...**.
3. In the alert, click **Delete**.

#### Repair a Damaged Active Profile List

If OJD can't read `ActiveProfiles.plist`, the area shows **Damaged Active Profile List**, and no profile is active.

1. Click **Back Up & Reset Active Profiles...**.
2. In the alert, click **Back Up & Reset**.

OJD keeps your profiles, but none is active afterward.

#### Find the Backup

OJD backs up each file before it changes it. The backup sits beside the file, in `~/Library/Application Support/OpenJoystickDriver/Profiles/` for a profile and one folder up for the list. The name is `FILE.backup-DATE-TIME-ID`. To recover data, open the copy in a text editor. See [Profile File Reference](Profile-File-Reference.md).

## Further Reading

- [Known issues](Known-Issues.md)
- [Frequently asked questions](FAQ.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Connection types](Connecting-Controllers.md)
- [How games see your controller](Playing-Games.md)
- [Importing and exporting profiles](Remapping-Profiles.md)
