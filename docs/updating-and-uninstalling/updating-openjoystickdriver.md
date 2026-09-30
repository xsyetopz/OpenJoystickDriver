# Updating OpenJoystickDriver

This article explains how to check for a new OpenJoystickDriver (OJD) version and how to get a fix.

## How update checks work

OJD checks for updates only when you ask. It has no timer and does not check in the background. An update check never downloads or installs anything.

A check reads the version tags of the OJD repository on GitHub and reports the highest version. By default it ignores prerelease versions. All current releases are prereleases (`0.5.0-beta.*`), so a default check may find nothing. To include prereleases, turn on **Include prerelease updates** in **Settings**. In the command line, add `--prerelease` to `update check`.

When a newer version exists, **View Update** opens the tag page in your browser. You download and install the new version yourself.

## Release builds and tester builds

A release build is a public DMG named `OpenJoystickDriver-VERSION-macOS.dmg`. The maintainer notarizes it.

A tester build is a private, notarized DMG that the maintainer sends to testers. It contains a fix that is not in a release yet. It also contains `OpenJoystickDriver-TESTER-BUILD.txt`, which names the commit and the build version. A tester build version has the form `VERSION+build.NUMBER.sha.COMMIT`.

An update check does not find tester builds. The maintainer sends them directly.

## Check for updates

1. Open OJD.
1. Open **Settings**.
1. In **Updates**, click **Check Now**.
1. If the result is **Update available**, click **View Update**.

To check from the terminal, run the following command. Add `--prerelease` to include prerelease versions.

```shell
ojd update check
```

## Install a new version

1. Quit OJD.
1. Open the new DMG.
1. Drag **OpenJoystickDriver** to **Applications**. Replace the old app when macOS asks.
1. Open OJD.

Your profiles stay in place because they are stored outside the app.

## Get a fix

If a bug is fixed in the source but not yet released, you have two options:

- Wait for the next tester build.
- Build the branch yourself. For more information, see [Building OpenJoystickDriver](../building-from-source/building-openjoystickdriver.md).

The `CHANGELOG.md` file in the repository lists what each build contains.

## Further reading

- [Known issues](../troubleshooting/known-issues.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
- [Uninstalling OpenJoystickDriver](uninstalling-openjoystickdriver.md)
