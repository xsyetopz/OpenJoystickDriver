# Updating and Uninstalling

Check for a new OpenJoystickDriver version, and remove the app and its data when you no longer need them.

## Contents

- [Update](#update)
  - [How Update Checks Work](#how-update-checks-work)
  - [Release Builds and Tester Builds](#release-builds-and-tester-builds)
  - [Check For Updates](#check-for-updates)
  - [Install a New Version](#install-a-new-version)
  - [Update from 0.6.0-alpha.1](#update-from-060-alpha1)
  - [Get a Fix](#get-a-fix)
- [Uninstall](#uninstall)
  - [Remove the App](#remove-the-app)
  - [Files That Stay On Your Mac](#files-that-stay-on-your-mac)
  - [Remove the Data](#remove-the-data)
- [Further Reading](#further-reading)

## Update

This section explains how to check for a new OpenJoystickDriver (OJD) version and how to get a fix.

### How Update Checks Work

OJD checks for updates only when you ask. It has no timer and does not check in the background. An update check never downloads or installs anything.

A check reads the version tags of the OJD repository on GitHub and reports the highest version. By default it ignores prerelease versions. A prerelease build is newer than every stable release, so a default check run from it finds nothing. To include prereleases, turn on **Include prerelease updates** in **Settings**. In the command line, add `--prerelease` to `update check`.

When a newer version exists, **View Update** opens the tag page in your browser. You download and install the new version yourself.

### Release Builds and Tester Builds

A release build is a public DMG named `OpenJoystickDriver-VERSION-macOS.dmg`. The maintainer notarizes it.

A tester build is a private, notarized DMG that the maintainer sends to testers. It contains a fix that is not in a release yet. It also contains `OpenJoystickDriver-TESTER-BUILD.txt`, which names the commit and the build version. A tester build version has the form `VERSION+build.NUMBER.sha.COMMIT`.

An update check does not find tester builds. The maintainer sends them directly.

### Check for Updates

1. Open OJD.
2. Open **Settings**.
3. In **Updates**, click **Check Now**.
4. If the result is **Update available**, click **View Update**.

To check from the terminal, run the following command. Add `--prerelease` to include prerelease versions.

```shell
ojd update check
```

### Install a New Version

1. Quit OJD.
2. Open the new DMG.
3. Drag **OpenJoystickDriver** to **Applications**. Replace the old app when macOS asks.
4. Open OJD.

Your profiles stay in place because they are stored outside the app.

### Update from 0.6.0-alpha.1

OJD 0.6.0-alpha.2 reads only files with `apiVersion: openjoystickdriver/v1alpha2`. It refuses each file from 0.6.0-alpha.1, which has `openjoystickdriver/v1alpha1`, with error `E5001`, and it does not change the file. The message names the file, the version it found, and the supported version.

| File | What OJD does | What you do |
| --- | --- | --- |
| `Settings.json` | The app shows an alert at launch. | Click **Reset Settings** in the alert, or run `ojd setting reset`. |
| `AccessGrants.json` | The endpoint stays off, and each `ojd access` command fails with `E5001`. | Change the `apiVersion` line to `openjoystickdriver/v1alpha2`, or move the file to the Trash and grant each program again. |
| Profiles in `Profiles/` | The profile shows as damaged. | Change the `apiVersion` line, then run `ojd profile validate FILE`. |
| Your controller records | OJD skips the file and uses the bundled record. `ojd record list` names it. | Change the `apiVersion` line, then run `ojd record validate FILE`. |
| Your virtual device files | OJD skips the file. | Change the `apiVersion` line. |
| Installed mods | `ojd mod validate` refuses the package. | Install a version of the mod made for 0.6.0-alpha.2. |

Change only the `apiVersion` line. When the validate command reports another error, the file uses a field that changed in this version; the `CHANGELOG.md` file lists those fields.

### Get a Fix

If a bug is fixed in the source but not yet released, you have two options:

- Wait for the next tester build.
- Build the branch yourself. For more information, see [Building OpenJoystickDriver](Building-from-Source.md).

The `CHANGELOG.md` file in the repository lists what each build contains.

## Uninstall

This section explains how to remove OpenJoystickDriver (OJD) and the files it leaves on your Mac.

Removing the app alone leaves a login item, privacy entries, a system extension, and data files. Follow the steps in order.

### Remove the App

1. Turn off the login item. Run the following command.

   ```shell
   ojd setting set launchAtLogin false
   ```

2. If you approved the OJD driver extension, remove it. In **Settings** > **Advanced**, under **Xbox USB Driver**, click **Uninstall**. Or run the following command.

   ```shell
   ojd transport-extension deactivate
   ```

3. Quit OJD from the menu bar item.
4. Move **OpenJoystickDriver** from **Applications** to the Trash.

Both commands work only from the copy in `/Applications`.

### Files That Stay on Your Mac

Removing the app does not remove these items.

| Item | Location |
| --- | --- |
| Profiles and profile backups | `~/Library/Application Support/OpenJoystickDriver/` |
| Your controller records | `~/Library/Application Support/OpenJoystickDriver/Controllers/` |
| Logs | `~/Library/Logs/OpenJoystickDriver/` |
| Settings | Preferences domain `com.openjoystickdriver` |
| Privacy entries | **System Settings** > **Privacy & Security** |

Each profile is a file in `Profiles/`, and `ActiveProfiles.json` lists the active profiles. Files whose names contain `.backup-` are recovery copies.

### Remove the Data

1. Remove the folder `~/Library/Application Support/OpenJoystickDriver`.
2. Remove the folder `~/Library/Logs/OpenJoystickDriver`.
3. Remove the settings. Run the following command.

   ```shell
   defaults delete com.openjoystickdriver
   ```

4. In **System Settings** > **Privacy & Security**, remove **OpenJoystickDriver** from **Input Monitoring** and **Accessibility**. Select the entry and click the minus button.

> [!NOTE]
> Export the profiles you want to keep before you remove the data. For more information, see [Importing and exporting profiles](Remapping-Profiles.md).

The notification entry stays in **System Settings** > **Notifications**. Not verified: whether macOS removes it by itself.

## Further Reading

- [Known issues](Known-Issues.md)
- [Reporting a bug](Reporting-a-Bug.md)
- [Permissions and security](Permissions-and-Security.md)
