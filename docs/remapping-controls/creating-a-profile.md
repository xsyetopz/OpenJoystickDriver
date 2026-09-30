# Creating a profile

This page explains how to create, activate, rename, duplicate, and delete a profile.

## Before you begin

- Connect the controller that the profile is for. The **Controller** list in the new profile sheet shows connected controllers. You can also select **Manual identifiers** and enter a vendor ID and product ID.
- Open the **Profiles** pane in the OpenJoystickDriver settings window.

## Create a profile in the app

1. In the **Profiles** pane, click the **New profile** button.
1. In the **New profile** sheet, enter a name. The default name is `My controller`.
1. Select the controller from the **Controller** list.
1. Select the application scope. For more information, see [About profiles](about-profiles.md).
1. Click **Create**.

The new profile has no assignments. It appears in the list with the label **Not active**.

To import a profile instead, click **Import profile**. For more information, see [Importing and exporting profiles](importing-and-exporting-profiles.md).

## Create a profile with the command line

```shell
ojd profile create "My controller" --controller 045E:02FD
```

Add `--app BUNDLE-ID` to limit the profile to one app. The new profile is inactive and passes through every control until you add bindings. The command needs the running app. For more information, see [Command reference](../command-line/command-reference.md).

## Activate a profile

1. Select the profile in the list.
1. Click **Set active**.

If the profile has no assignments and suppresses all controller input, the app shows the alert **Activate profile with no controller input?**. Click **Set active** only if you want that result. To restore default input, click **Restore default input** first.

To deactivate the profile, click **Deactivate**. To deactivate every profile for the controller, open the **Profile actions** menu and select **Deactivate all**.

The command line equivalents are:

```shell
ojd profile activate "My controller"
ojd profile deactivate "My controller"
```

The `activate` command refuses a profile that suppresses all input. Add `--allow-empty` to override. Paired Joy-Con profiles have no **Set active** button. For more information, see [Sticks, triggers, touchpad, and motion](sticks-triggers-touchpad-and-motion.md).

## Save changes

The editor shows the save state at the bottom: **Unsaved changes**, **Saving...**, **Saved**, or **Save failed**. Click **Save** to store your edits. If you select another profile with unsaved changes, the app asks **Discard unsaved changes?**.

If another process changes the profile, the app shows **This profile changed elsewhere. Reload or keep editing.** Click **Reload** to load the new version or **Keep editing** to keep your draft.

## Rename or change the controller and scope

1. Select the profile.
1. Click the pencil button, **Profile details**.
1. Change **Profile name**, **Vendor ID**, **Product ID**, or **Target**.
1. If you select **One application**, enter the **Bundle identifier**. The app has no running-app picker.
1. Click **Apply**, then click **Save**.

To rename a profile on the command line, run `ojd profile rename PROFILE NEW-NAME`. To change the controller model or the app, run `ojd profile edit PROFILE` and change `device` or `applicationScope` in the profile file.

## Duplicate a profile

1. Select the profile.
1. Open the **Profile actions** menu.
1. Select **Duplicate**.

The copy is named `NAME Copy`. Profile names must be unique. The command line equivalent is `ojd profile duplicate PROFILE NEW-NAME`.

## Delete a profile

1. Select the profile.
1. Click the red **Delete** button at the bottom of the editor.
1. In the alert **Delete profile?**, click **Delete**.

The command line equivalent is `ojd profile delete PROFILE`.

## Clear all assignments

1. Open the **Profile actions** menu.
1. Select **Clear all inputs**.
1. Confirm the alert **Clear all inputs?**.

This clears all assignments and input processing from the profile. To return to pass-through, select **Restore default input**.

The command line has no equivalent that also clears input processing. `ojd binding clear PROFILE --all` removes every assignment, combination, sequence, and layer, and keeps stick, trigger, touch, motion, and output settings. To return to pass-through, run `ojd profile edit PROFILE` and set `virtualGamepad` to `passthrough`.

## Further reading

- [Assigning buttons and actions](assigning-buttons-and-actions.md)
- [About profiles](about-profiles.md)
- [Known issues](../troubleshooting/known-issues.md)
