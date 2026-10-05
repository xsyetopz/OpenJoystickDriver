# Create a Local Tester Build

This page is for maintainers. Testers use [Test a tester build](../testing/tester-builds.md).

Use this guide to create a DMG for users who test an unpublished build. The command signs, notarizes, staples, and packages the app. It does not install or publish the build.

## Requirements

Only a developer with the approved Apple assets can create a shareable build. You need:

- A Developer ID Application certificate in the login keychain.
- Separate Developer ID profiles for the app and DriverKit extension.
- Apple notarization credentials.
- A clean Git worktree at the exact commit that users will test.

Apple Development builds are valid only on registered Macs. Do not send them to community testers. See [Signing](signing.md) for the required app, extension, and entitlement configuration.

## 1. Prepare Signing

Install the profiles and create the local environment files:

```bash
just signing-install-profiles
just signing-configure
```

The scripts store local configuration in `.env.dev` and `.env.release`. Do not commit these files. Do not send certificates, profiles, passwords, or environment files to testers.

If notarization credentials are not already in the keychain, store them:

```bash
just release-notarize-store-credentials
```

## 2. Check the Environment

Run the tester-build checks:

```bash
just package-tester-check
```

This command checks the release environment and signing assets. It does not build, install, notarize, or publish an app.

Commit or remove all intended source changes before packaging. The package command stops when the worktree is not clean. This rule keeps the DMG metadata tied to one Git commit.

## 3. Create the DMG

Run:

```bash
just package-tester
```

The command performs these operations:

1. It builds the Developer ID app.
1. It builds and embeds the DriverKit extension.
1. It checks versions, signatures, entitlements, notarization, stapling, and Gatekeeper acceptance.
1. It creates and checks the tester DMG.

Notarization time depends on Apple. A repeated submission usually takes minutes. A first submission can take hours.

The final file is in:

```text
.build/tester-artifacts/OpenJoystickDriver-*-tester-*-macOS.dmg
```

The DMG also contains `OpenJoystickDriver-TESTER-BUILD.txt`. This file identifies the source commit, version, bundle build number, signing type, and notarization result. The version is the release SemVer with build metadata, such as `0.5.0-beta.5+build.1.14.89.sha.0123456789ab`.

## 4. Send the Build

Send the DMG without changing its contents, with the [tester instructions](../testing/tester-builds.md). Testers must attach the support report and `OpenJoystickDriver-TESTER-BUILD.txt` to the issue. For controller-record tests, they also follow [Test A Controller Record](../testing/controller-record.md).

## Failures

| Failure | Required action |
| --- | --- |
| The worktree is not clean. | Commit the exact test changes, then run the package command again. |
| A profile or entitlement does not match. | Run `just signing-configure`, then run `just package-tester-check`. |
| Notarization credentials are missing. | Run `just release-notarize-store-credentials`. |
| Notarization fails. | Read the submission log with `just release-notarize-log <id>`. |
| Gatekeeper or stapling fails. | Do not send the DMG. Fix signing, then create a new tester build. |

Do not bypass signing checks or change the app after notarization. A changed bundle has an invalid resource seal and is not the tested artifact.
