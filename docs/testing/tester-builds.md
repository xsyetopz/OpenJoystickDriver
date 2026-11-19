# Test a Tester Build

A tester build is a DMG of a build that isn't released yet, made to check whether a fix works. It's notarized and signed with Developer ID, so macOS trusts it. You don't need an Apple developer account. Maintainers, see [Create a local tester build](../development/tester-builds.md).

## Get and Install a Tester Build

1. Get the DMG exactly as it was published, from one of these:
   - the pre-release linked in your issue, or the [pre-release list](https://github.com/xsyetopz/OpenJoystickDriver/releases)
   - **Settings**: turn on **Include prerelease updates** and click **Check Now**. See [Updating](../../wiki/Updating-and-Uninstalling.md#release-builds-and-tester-builds).
   - the maintainer
2. Drag `OpenJoystickDriver.app` to `/Applications`.
3. Open the app and approve the macOS permissions in the order shown in [Install](../../wiki/Getting-Started.md#installing-openjoystickdriver). Approve the driver extension only if you have one of the [seven Microsoft models](../../wiki/Supported-Controllers.md#supported-controllers).
4. Make the problem happen again.

## What's in the DMG

- `OpenJoystickDriver.app`
- `OpenJoystickDriver-TESTER-BUILD.txt`, which lists the source commit, version, build number, signing type, and notarization result

The version is the release version plus build details, such as `0.5.0-beta.5+build.1.14.89.sha.0123456789ab`.

## Report the Build

1. Attach `OpenJoystickDriver-TESTER-BUILD.txt` to your issue.
2. Say whether it fixed the problem. `CHANGELOG.md` lists what changed.
3. Add the support report and captures from [Report a bug](../../wiki/Reporting-a-Bug.md).

To test a controller record too, see [Test a controller record](controller-record.md).
