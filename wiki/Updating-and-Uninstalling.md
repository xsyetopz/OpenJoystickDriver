# Updating and Uninstalling

Update OpenJoystickDriver (OJD), or remove the app and its data from your Mac.

## Contents

- [Update](#update)
  - [How Update Checks Work](#how-update-checks-work)
  - [Release Builds and Tester Builds](#release-builds-and-tester-builds)
  - [Check for Updates](#check-for-updates)
  - [Install an Update](#install-an-update)
  - [Update from an Earlier Alpha](#update-from-an-earlier-alpha)
  - [Get a Fix](#get-a-fix)
- [Uninstall](#uninstall)
  - [Remove the App](#remove-the-app)
  - [Files That Stay on Your Mac](#files-that-stay-on-your-mac)
  - [Remove the Data](#remove-the-data)
- [Further Reading](#further-reading)

## Update

### How Update Checks Work

OJD checks for updates only when you ask. If you turn on **Check for updates automatically** in the **General** pane of **Settings**, it also checks once at each launch and once when you turn the setting on. A check never downloads or installs anything.

A check reads the version tags of the OJD repository on GitHub and reports the highest version. It ignores prereleases by default, so a check from a prerelease build finds nothing. To include them, turn on **Include prerelease updates** in **Settings**, or add `--prerelease` to `ojd update check`.

**View Update** opens the version's page in your browser. You install it yourself.

### Release Builds and Tester Builds

A release build is a public, notarized DMG named `OpenJoystickDriver-VERSION-macOS.dmg`.

A tester build is a notarized DMG with a fix that isn't in a release. It appears on the [GitHub Releases page](https://github.com/xsyetopz/OpenJoystickDriver/releases) and is linked from the issue it answers. `0.6.0-alpha.2.tester.1` comes after `0.6.0-alpha.2` and before `0.6.0-alpha.3`.

A DMG sent directly holds `OpenJoystickDriver-TESTER-BUILD.txt`, which names the commit and build version.

### Check for Updates

1. Choose OpenJoystickDriver > **Settings...**.
2. In **Updates** on the **General** pane, click **Check Now**.

   ![The General pane of Settings. A red arrow points to Check Now, which asks GitHub for a newer OJD and installs nothing](../docs/screenshots/steps/check-for-updates.png)

3. If it says **Update available**, click **View Update**.

Or run this in Terminal:

```shell
ojd update check
```

### Install an Update

1. Quit OJD.
2. Open the downloaded DMG.
3. Drag **OpenJoystickDriver** to **Applications**. Click **Replace**.
4. Open OJD from **Applications**.
5. If OJD shows **Repair Xbox USB Driver**, click it.
6. Unplug each USB controller that uses the [Xbox USB driver](Glossary.md#terms), then plug it in again. Otherwise macOS can keep the old driver.

> [!IMPORTANT]
> Open OJD from **Applications**, not from the DMG. macOS turns on the Xbox USB driver only for an app in **Applications**.

Your [profiles](Glossary.md#terms) stay in place.

After an update, **Driver Extensions** in **System Settings** can list the old driver until you restart. You don't need to remove it.

If **Input Monitoring** or **Accessibility** shows OJD as allowed but OJD reads no controller, remove OJD from the list and add it again:

1. Choose Apple menu > **System Settings**, then click **Privacy & Security**.
2. Click **Input Monitoring** (or **Accessibility**), select **OpenJoystickDriver**, and click **-**.
3. Click **+** and choose **OpenJoystickDriver** in **Applications**.

If OJD isn't in the list, see [If OpenJoystickDriver Isn't in the List](Permissions-and-Security.md#if-openjoystickdriver-isnt-in-the-list).

### Update from an Earlier Alpha

OJD 0.6.0-alpha.3 reads only XML property list files (`.plist`) with `apiVersion: openjoystickdriver/v1alpha3`. Files from alpha.1 and alpha.2 are JSON and fail with `E5001`. A file that isn't an XML property list fails with `E5010`.

OJD converts old files each time the service starts. You can also run it yourself:

```sh
ojd migrate --dry-run
ojd migrate
```

`--dry-run` lists what would convert and writes nothing. `ojd migrate` writes each converted `.plist` beside the original and copies the original to `Migrated/` in the OJD support folder. Each file gets one verdict: `Migrated`, `Current`, `Failed`, or `Foreign`. A file it can't convert stays unchanged, and the command exits with `E5009`. `ojd migrate FOLDER` scans a folder you name. For `E5001`, the app offers **Migrate** next to the error.

A file from 0.5 has no `apiVersion`, so create the profile again. `ojd mod validate` refuses a mod that isn't a `v1alpha3` package.

### Get a Fix

For an unreleased fix, wait for a tester build or build the branch yourself. See [Building From Source](Building-from-Source.md). `CHANGELOG.md` lists what each build contains.

## Uninstall

Moving the app to the Trash leaves a login item, privacy entries, the [Xbox USB driver](Glossary.md#terms), and data files on your Mac. Follow the steps in order.

### Remove the App

1. Turn off the login item. In **Settings** > **General**, turn off **Start at login**. Or run this command.

   ```shell
   ojd setting set launchAtLogin false
   ```

2. If you approved the Xbox USB driver, remove it. In **Settings** > **Advanced**, under **Xbox USB Driver**, click **Uninstall**. Or run this command.

   ```shell
   ojd transport-extension deactivate
   ```

3. Click the OJD icon in the menu bar and choose **Quit OpenJoystickDriver**.
4. Drag **OpenJoystickDriver** from **Applications** to the Trash.

The driver commands work only with the copy in `/Applications`.

### Files That Stay on Your Mac

| Item | Location |
| --- | --- |
| Profiles and profile backups | `~/Library/Application Support/OpenJoystickDriver/` |
| Your controller records | `~/Library/Application Support/OpenJoystickDriver/Controllers/` |
| Logs | `~/Library/Logs/OpenJoystickDriver/` |
| Settings | Preferences domain `com.openjoystickdriver` |
| Privacy entries | **System Settings** > **Privacy & Security** |

Files whose names contain `.backup-` are recovery copies.

### Remove the Data

1. Move the folder `~/Library/Application Support/OpenJoystickDriver` to the Trash.
2. Move the folder `~/Library/Logs/OpenJoystickDriver` to the Trash.
3. Remove the settings. Run this command.

   ```shell
   defaults delete com.openjoystickdriver
   ```

4. In **System Settings** > **Privacy & Security**, click **Input Monitoring**, select **OpenJoystickDriver**, and click **-**. Do the same in **Accessibility**.

> [!NOTE]
> Export the profiles you want to keep before you remove the data. See [Importing and exporting profiles](Remapping-Profiles.md#importing-and-exporting-profiles).

The notification entry stays in **System Settings** > **Notifications**. Whether macOS removes it is untested.

## Further Reading

- [Known issues](Known-Issues.md)
- [Reporting a Bug](Reporting-a-Bug.md)
- [Permissions and Security](Permissions-and-Security.md)
