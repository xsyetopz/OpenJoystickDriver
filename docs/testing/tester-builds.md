# Test a Tester Build

A tester build is a notarized DMG of an unpublished build, made by the maintainer so you can check a fix. It is not the same as a build you compile yourself: it is signed with Developer ID and works without any Apple developer account. Maintainers: see [Create a local tester build](../development/tester-builds.md).

## Get and Install One

The maintainer sends you the DMG. Do not change its contents.

1. Open the DMG and drag `OpenJoystickDriver.app` to `/Applications`.
1. Open the app and approve the macOS permissions it asks for, in the order in [Install](../../wiki/Getting-Started.md#installing-openjoystickdriver). Approve the driver extension only if your controller is one of the [seven Microsoft models](../../wiki/Supported-Controllers.md#supported-controllers).
1. Reproduce the problem with the packaged app.

## What Is In the DMG

`OpenJoystickDriver.app` and `OpenJoystickDriver-TESTER-BUILD.txt`. The text file names the source commit, version, bundle build number, signing type, and notarization result. The version is the release SemVer plus build metadata, such as `0.5.0-beta.5+build.1.14.89.sha.0123456789ab`.

## Report the Build

Attach `OpenJoystickDriver-TESTER-BUILD.txt` to your issue, and say which build fixed or did not fix the problem. To see what changed, read `CHANGELOG.md` in the repository. Then add the support report and any capture from [Report a bug](../../wiki/Reporting-a-Bug.md).

For controller-record tests, also follow [Test a controller record](controller-record.md).
