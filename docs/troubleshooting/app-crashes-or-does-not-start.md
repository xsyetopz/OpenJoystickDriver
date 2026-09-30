# App crashes or does not start

This article explains what to do when OpenJoystickDriver (OJD) crashes, does not start, or reports a damaged profile library.

## Collect information

1. Open the Console pane, or run the following command.

   ```shell
   ojd log show --lines 200
   ```

1. Note what you did before the crash.
1. Report it. For more information, see [Reporting a bug](reporting-a-bug.md).

OJD clears its log files at each start. Copy the logs before you start OJD again.

## Crash at every start

If OJD crashes at every start, two global profiles may be active for one controller model. This is a known issue.

1. Quit OJD.
1. Move `~/Library/Application Support/OpenJoystickDriver/RemappingProfiles.json` to another folder.
1. Open OJD.

## Crash when you unplug a controller

Unplugging a USB controller or dongle may crash OJD. Open OJD again. Restart OJD if stale virtual controllers stay in **System Settings**.

## Damaged profile library

OJD reads the profile file at start. It does not change the file when it finds damage. While damage exists, OJD blocks every change to the profile library until you repair it.

OJD shows two kinds of damage in the **Profiles** pane.

### One damaged profile

OJD keeps the valid profiles and marks the damaged profile **Needs attention**.

1. Select the damaged profile.
1. Click **Delete Damaged Profile...**.
1. In the alert, click **Delete**.

OJD saves a backup before it changes the file.

### Unreadable library

If OJD cannot use the whole file, the pane shows **Profile library** and the message "Profiles could not be loaded."

1. Click **Back Up & Reset Library...**.
1. In the alert, click **Back Up & Reset**.

OJD saves a backup and then writes an empty library. Your profiles are not in the active library after this step.

### Find the backup

Backups are in `~/Library/Application Support/OpenJoystickDriver/`. The name has the form `RemappingProfiles.json.backup-DATE-TIME-ID`. The time is local time.

A backup is a copy of the file as it was before repair. To recover data, open the copy in a text editor. For more information, see [Profile file reference](../remapping-controls/profile-file-reference.md).

## Further reading

- [Known issues](known-issues.md)
- [Importing and exporting profiles](../remapping-controls/importing-and-exporting-profiles.md)
