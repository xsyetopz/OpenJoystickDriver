# Uninstalling OpenJoystickDriver

This article explains how to remove OpenJoystickDriver (OJD) and the files it leaves on your Mac.

Removing the app alone leaves a login item, privacy entries, a system extension, and data files. Follow the steps in order.

## Remove the app

1. Turn off the login item. Run the following command.

   ```shell
   ojd setting set launch-at-login false
   ```

1. If you approved the Xbox USB system extension, remove it. In **Overview**, on the **Xbox USB Driver** card, click **Uninstall**. Or run the following command.

   ```shell
   ojd extension deactivate
   ```

1. Quit OJD from the menu bar item.
1. Move **OpenJoystickDriver** from **Applications** to the Trash.

Both commands work only from the copy in `/Applications`.

## Files that stay on your Mac

Removing the app does not remove these items.

| Item | Location |
| --- | --- |
| Profiles and profile backups | `~/Library/Application Support/OpenJoystickDriver/` |
| Your controller records | `~/Library/Application Support/OpenJoystickDriver/Controllers/` |
| Logs | `~/Library/Logs/OpenJoystickDriver/` |
| Settings | Preferences domain `com.openjoystickdriver` |
| Privacy entries | **System Settings** > **Privacy & Security** |

The profile file is `RemappingProfiles.json`. Files that start with `RemappingProfiles.json.backup-` are recovery copies.

## Remove the data

1. Remove the folder `~/Library/Application Support/OpenJoystickDriver`.
1. Remove the folder `~/Library/Logs/OpenJoystickDriver`.
1. Remove the settings. Run the following command.

   ```shell
   defaults delete com.openjoystickdriver
   ```

1. In **System Settings** > **Privacy & Security**, remove **OpenJoystickDriver** from **Input Monitoring** and **Accessibility**. Select the entry and click the minus button.

> [!NOTE]
> Export the profiles you want to keep before you remove the data. For more information, see [Importing and exporting profiles](../remapping-controls/importing-and-exporting-profiles.md).

The notification entry stays in **System Settings** > **Notifications**. Not verified: whether macOS removes it by itself.

## Further reading

- [Updating OpenJoystickDriver](updating-openjoystickdriver.md)
- [Permissions](../permissions-and-security/permissions.md)
