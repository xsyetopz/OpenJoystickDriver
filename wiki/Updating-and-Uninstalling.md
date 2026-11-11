# Updating and Uninstalling

Check for a new OpenJoystickDriver version, and remove the app and its data when you no longer need them.

## Contents

- [Update](#update)
  - [How Update Checks Work](#how-update-checks-work)
  - [Release Builds and Tester Builds](#release-builds-and-tester-builds)
  - [Check For Updates](#check-for-updates)
  - [Install a New Version](#install-a-new-version)
  - [Update from an Earlier Alpha](#update-from-an-earlier-alpha)
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

A tester build is a notarized DMG with a fix that is not in a release yet. The maintainer publishes it as a pre-release on the [GitHub Releases page](https://github.com/xsyetopz/OpenJoystickDriver/releases) and links it from the issue it answers. Its version names the release before it: `0.6.0-alpha.2.tester.1` comes after `0.6.0-alpha.2` and before `0.6.0-alpha.3`. A tester build of the first release after a stable `0.5.0` is `0.5.1-tester.1`.

An update check finds a tester build only when **Include prerelease updates** is on in **Settings** (`--prerelease` in `ojd update check`). With it on, a check from a release offers the newest tester build, and a check from a tester build offers the release it leads to. With it off, a check offers stable releases only.

A DMG that the maintainer builds locally and sends directly contains `OpenJoystickDriver-TESTER-BUILD.txt`, which names the commit and the build version, in the form `VERSION+build.NUMBER.sha.COMMIT`.

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

### Update from an Earlier Alpha

OJD 0.6.0-alpha.3 reads only XML property list files (`.plist`) with `apiVersion: openjoystickdriver/v1alpha3`. Files from 0.6.0-alpha.1 are JSON with `openjoystickdriver/v1alpha1`, and files from 0.6.0-alpha.2 are JSON with `openjoystickdriver/v1alpha2`. OJD opens neither. A file with another version fails with error `E5001`, and a file that is not an XML property list fails with `E5010`. Migrate the files first. The message names the file, the version or form it found, and the supported one.

OJD converts these files for you. The service runs the migration each time it starts, before anything reads a file, and logs one verdict per file. You can run it yourself:

```sh
ojd migrate --dry-run
ojd migrate
```

`--dry-run` lists what would be converted and writes nothing. `ojd migrate` writes each converted file as a `.plist` beside the original and copies the original to `Migrated/` in the OJD support folder, with its relative path. A backup is never overwritten. Each file gets one verdict: `Migrated`, `Current`, `Failed` or `Foreign`. A file it cannot convert stays unchanged, the other files still convert, and the command exits with error `E5009` and names the file and the reason. `ojd migrate FOLDER` scans a folder you name, such as a copy of your old files or a mod you wrote, and keeps its backups in `FOLDER/Migrated/`.

When OJD shows `E5001` for a file, the app offers **Migrate** next to the error, before it offers to delete the file. A `.json` file left in a store folder is named in the message.

A file from 0.5 has no `apiVersion`. It gets the verdict `failed` with "written by 0.5; re-create it": create the profile again in the app.

`ojd mod validate` refuses a mod package that is not a `v1alpha3` package. Install a version of the mod made for 0.6.0-alpha.3.

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

Each profile is a file in `Profiles/`, and `ActiveProfiles.plist` lists the active profiles. Files whose names contain `.backup-` are recovery copies.

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
