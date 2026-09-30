# Console and settings

The **Console** pane shows OpenJoystickDriver logs. The **Settings** pane controls login, notifications, updates, and developer tools.

## Console pane

Open **Console** from the sidebar or from **Help** > **Open Console...** in the menu-bar menu.

- **Stream** selects **All**, **Output**, or **Errors**.
- **Refresh** reads the logs again.
- **Copy All** copies the shown lines.

If there are no lines, the pane shows **No log entries.** Each start of OJD clears the logs. For more information, see [Reporting a bug](../troubleshooting/reporting-a-bug.md).

## Settings pane

Open **Settings** from the sidebar or press <kbd>Command</kbd>+<kbd>,</kbd>.

### General

**Start at login** opens OJD in the menu bar when you log in. It needs macOS 13 or later. If macOS needs approval, allow OJD in **System Settings** > **General** > **Login Items**.

> [!NOTE]
> The **Start at login** switch removes the login item but does not record that you opted out. At the next start, OJD registers itself again. This is what the source code does. It is not verified on a running system. To stay opted out, run the `app login disable` command. For more information, see [Command reference](../command-line/command-reference.md).

### Notifications

Turn notifications on for these events:

- **Controllers**: **Connected** and **Disconnected**.
- **Profiles**: **Activated or switched** and **Deactivated**.
- **Play a sound**.

Click **Send Test Notification** to test delivery. If macOS denies notifications, OJD turns the toggles off. Click **Open Notification Settings** to fix this.

### Updates

Click **Check Now** to look for a newer version. OJD contacts GitHub only when you click it. The result is **Up to date**, **Update available**, or **Update check failed**. Click **View Update** to open the release page. OJD does not download or install anything. Select **Include prerelease updates** to include beta versions.

### Developer Tools

Select **Enable Developer Tools** to add the **Developer Tools** pane. It shows controller input and USB packet tools. For more information, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).

## Further reading

- [Updating OpenJoystickDriver](../updating-and-uninstalling/updating-openjoystickdriver.md)
- [Permissions](../permissions-and-security/permissions.md)
