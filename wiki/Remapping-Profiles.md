# Remapping Profiles

Profiles change what your controller buttons, sticks, triggers, touchpad, and motion sensors do.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [About Profiles](#about-profiles)
- [Creating a Profile](#creating-a-profile)
- [Importing and Exporting Profiles](#importing-and-exporting-profiles)
- [Further Reading](#further-reading)

## About Profiles

A profile is a saved set of remapping rules for one controller model.

This section explains what a profile contains, how OpenJoystickDriver (OJD) picks the active profile, and what output policy means.

### What a Profile Contains

Each profile has a name, a controller model, and an application scope. The controller model is a vendor ID and product ID pair. For more information, see [Finding your controller ID](Connecting-Controllers.md).

A profile can also contain these items:

- Assignments that map one control to one destination
- Chords, sequences, and layers
- Stick, trigger, touch, and motion settings
- An output policy
- A lighting color

A profile applies to every connected controller of its model.

### Scope

The scope decides when a profile is eligible to work.

- **All applications** (global): The profile works in every app.
- **One application**: The profile works only while one app is in front. You identify the app with its bundle identifier, for example `com.apple.Safari`.

### The Active Profile

A profile does nothing until you activate it. One controller model can have several active profiles, one for each application scope.

OJD picks the profile for a controller in this order:

1. The most recently activated profile whose application scope matches the front app.
1. The most recently activated global profile.
1. The most recently activated profile for the model, even if its scope is an app that is not in front.

If no profile is active, OJD passes the controller through to the virtual controller. An app-scoped profile picked by rule 3 does not work until its app is in front.

OJD reads the front app when a controller connects, and when you activate, deactivate, or edit a profile. Whether OJD re-evaluates the choice at the instant you switch apps is not verified.

> [!WARNING]
> Do not activate a second global profile for a model that already has one. Two active global profiles for one model crash the app at every launch. For more information, see [Known issues](Known-Issues.md).

### Output Policy

The output policy decides how a profile sends its results. It has two settings.

| Setting | Values | Meaning |
| --- | --- | --- |
| Virtual gamepad | Disabled, Mapped controls only, Include unmapped controls | Whether OJD publishes a virtual controller for this profile |
| Require exclusive physical input | Off, On | Whether OJD takes exclusive ownership of the physical input |

- **Disabled**: OJD sends keyboard and pointer events only. There is no virtual controller output.
- **Mapped controls only**: OJD sends only the destinations that you assigned.
- **Include unmapped controls**: OJD also forwards controls that no assignment uses.

Virtual gamepad output needs exclusive physical input. A profile that you create in the app starts with **Include unmapped controls** and no assignments.

A profile that sends keyboard or pointer events needs Accessibility access. For more information, see [Permissions](Permissions-and-Security.md).

## Creating a Profile

This section explains how to create, activate, rename, duplicate, and delete a profile.

### Before You Begin

- Connect the controller that the profile is for. The **Controller** list in the new profile sheet shows connected controllers. You can also select **Manual identifiers** and enter a vendor ID and product ID.
- Open the **Profiles** pane in the OpenJoystickDriver settings window.

### Create a Profile In the App

1. In the **Profiles** pane, click the **New profile** button.
1. In the **New profile** sheet, enter a name. The default name is `My controller`.
1. Select the controller from the **Controller** list.
1. Select the application scope. For more information, see [About profiles](#about-profiles).
1. Click **Create**.

The new profile has no assignments. It appears in the list with the label **Not active**.

To import a profile instead, click **Import profile**. For more information, see [Importing and exporting profiles](#importing-and-exporting-profiles).

### Create a Profile With the Command Line

```shell
ojd profile create "My controller" --controller 045E:02FD
```

Add `--app BUNDLE-ID` to limit the profile to one app. The new profile is inactive and passes through every control until you add bindings. The command needs the running app. For more information, see [Command reference](Command-Reference.md).

### Activate a Profile

1. Select the profile in the list.
1. Click **Set active**.

If the profile has no assignments and suppresses all controller input, the app shows the alert **Activate profile with no controller input?**. Click **Set active** only if you want that result. To restore default input, click **Restore default input** first.

To deactivate the profile, click **Deactivate**. To deactivate every profile for the controller, open the **Profile actions** menu and select **Deactivate all**.

The command line equivalents are:

```shell
ojd profile activate "My controller"
ojd profile deactivate "My controller"
```

The `activate` command refuses a profile that suppresses all input. Add `--allow-empty` to override. Paired Joy-Con profiles have no **Set active** button. For more information, see [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md).

### Save Changes

The editor shows the save state at the bottom: **Unsaved changes**, **Saving...**, **Saved**, or **Save failed**. Click **Save** to store your edits. If you select another profile with unsaved changes, the app asks **Discard unsaved changes?**.

If another process changes the profile, the app shows **This profile changed elsewhere. Reload or keep editing.** Click **Reload** to load the new version or **Keep editing** to keep your draft.

### Rename Or Change the Controller and Scope

1. Select the profile.
1. Click the pencil button, **Profile details**.
1. Change **Profile name**, **Vendor ID**, **Product ID**, or **Target**.
1. If you select **One application**, enter the **Bundle identifier**. The app has no running-app picker.
1. Click **Apply**, then click **Save**.

To rename a profile on the command line, run `ojd profile rename PROFILE NEW-NAME`. To change the controller model or the app, run `ojd profile edit PROFILE` and change `device` or `applicationScope` in the profile file, or run `ojd profile set PROFILE applicationScope '{"type":"global"}'`.

### Duplicate a Profile

1. Select the profile.
1. Open the **Profile actions** menu.
1. Select **Duplicate**.

The copy is named `NAME Copy`. Profile names must be unique. The command line equivalent is `ojd profile duplicate PROFILE NEW-NAME`.

### Delete a Profile

1. Select the profile.
1. Click the red **Delete** button at the bottom of the editor.
1. In the alert **Delete profile?**, click **Delete**.

The command line equivalent is `ojd profile delete PROFILE`.

### Clear All Assignments

1. Open the **Profile actions** menu.
1. Select **Clear all inputs**.
1. Confirm the alert **Clear all inputs?**.

This clears all assignments and input processing from the profile. To return to pass-through, select **Restore default input**.

The command line has no equivalent that also clears input processing. `ojd binding clear PROFILE --all` removes every assignment, combination, sequence, and layer, and keeps stick, trigger, touch, motion, and output settings. To return to pass-through, run `ojd profile set PROFILE outputPolicy.virtualGamepad passthrough`.

## Importing and Exporting Profiles

This section explains how to save a profile to a JSON file and how to load a profile from a file.

Use export and import to keep a copy of a profile, to share it, or to move it to a different Mac.

### Export a Profile

1. Open the **Profiles** pane.
1. Select the profile.
1. Click **Profile actions**, then select **Export**.
1. Select a folder and a file name. The default name is `PROFILE-NAME.json`.
1. Click **Save**.

The command line equivalent prints the profile JSON, or writes it to a file. The examples use the `ojd` alias. For more information, see [Using the command line](Command-Line.md).

```shell
ojd profile export PROFILE --output FILE.json
```

### Import a Profile

1. Open the **Profiles** pane.
1. Click **Import profile**.
1. Select a JSON file.
1. Click **Open**.

The command line equivalent is:

```shell
ojd profile import FILE.json
```

OJD checks the file before it adds the profile. OJD rejects a file with unknown keys, values out of range, or a size above 4 MiB.

### What Happens On Import

- If OJD has a profile with the same `id`, the imported profile replaces it.
- If OJD has no profile with that `id`, OJD adds the imported profile.
- If a different profile already uses the same name, OJD rejects the import.
- If the replaced profile was active and the imported profile has a different controller model, OJD deactivates it.

A new imported profile is not active until you activate it. For more information, see [Creating a profile](#creating-a-profile).

### Recover Damaged Profile Files

OJD skips a profile file that it cannot read, and it reports the file in Settings and in `ojd profile list`. A damaged active profile list is reported the same way. For more information, see [Profile file reference](Profile-File-Reference.md#damaged-files).

1. Run `ojd profile list` to see each damaged file.
1. Run `ojd profile recover --dry-run` to see what the command would change. This changes nothing.
1. Run `ojd profile recover`.
1. If the command asks for confirmation, confirm it.

The command removes each damaged profile file and resets a damaged active profile list. Before it removes or resets a file, the service saves a backup beside the original, under a name that contains `.backup-`. The command asks for confirmation on a terminal. Without a terminal, add `--force`.

## Further Reading

- [Profile file reference](Profile-File-Reference.md)
- [Bindings and actions](Bindings-and-Actions.md)
- [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md)
- [How games see your controller](Playing-Games.md)
- [Known issues](Known-Issues.md)
- [Troubleshooting](Troubleshooting.md)
