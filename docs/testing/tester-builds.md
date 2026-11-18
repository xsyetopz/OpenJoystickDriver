# Test a Tester Build

A tester build is a notarized, Developer ID signed DMG of an unpublished build, made to check a fix. No Apple developer account needed. Maintainers: see [Create a local tester build](../development/tester-builds.md).

## Get and Install a Tester Build

1. Get the unmodified DMG:
   - From the pre-release linked in your issue, or the [pre-release list](https://github.com/xsyetopz/OpenJoystickDriver/releases).
   - **Settings**: turn on **Include prerelease updates**, click **Check Now**. See [Updating](../../wiki/Updating-and-Uninstalling.md#release-builds-and-tester-builds).
   - From the maintainer.
2. Drag `OpenJoystickDriver.app` to `/Applications`.
3. Open the app; approve macOS permissions in the order in [Install](../../wiki/Getting-Started.md#installing-openjoystickdriver). Approve the driver extension only for one of the [seven Microsoft models](../../wiki/Supported-Controllers.md#supported-controllers).
4. Reproduce the problem.

## DMG Contents

`OpenJoystickDriver.app` and `OpenJoystickDriver-TESTER-BUILD.txt` (source commit, version, build number, signing type, notarization result). Version is release SemVer plus build metadata, such as `0.5.0-beta.5+build.1.14.89.sha.0123456789ab`.

## Report the Build

1. Attach `OpenJoystickDriver-TESTER-BUILD.txt` to your issue.
2. State whether it fixed the problem. `CHANGELOG.md` lists changes.
3. Add the support report and captures from [Report a bug](../../wiki/Reporting-a-Bug.md).

Record tests also need [Test a controller record](controller-record.md).
