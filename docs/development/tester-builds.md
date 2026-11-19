# Create a Local Tester Build

For maintainers. Testers use [Test a tester build](../testing/tester-builds.md).

These steps make a DMG of a build that isn't published, so a tester can try it. The DMG gets Apple's signature and notarization stamp, like a sealed envelope. The steps install nothing and publish nothing.

## Requirements

You need:

- A Developer ID Application certificate in the login keychain.
- Developer ID profiles for the app and the DriverKit extension.
- Apple notarization credentials.
- A clean worktree at the commit to test.

Apple Development builds run only on registered Macs, so do not send them. [Signing](signing.md) lists the configuration.

## 1. Prepare Signing

Install the profiles and create the environment files:

```bash
just signing-install-profiles
just signing-configure
```

The scripts write `.env.dev` and `.env.release`. Never commit them or send them to testers.

Store notarization credentials if missing:

```bash
just release-notarize-store-credentials
```

## 2. Check the Environment

Check the signing files:

```bash
just signing-audit
```

The package command stops if the worktree has uncommitted changes, so commit or remove them first.

## 3. Create the DMG

Run:

```bash
just package-tester
```

The command:

1. Builds the Developer ID app.
2. Builds and embeds the DriverKit extension.
3. Checks versions, signatures, entitlements, notarization, stapling, and Gatekeeper.
4. Creates and checks the DMG.

Notarization takes minutes for a repeat submission and hours for a first.

The DMG is in:

```text
.build/tester-artifacts/OpenJoystickDriver-*-tester-*-macOS.dmg
```

The DMG holds `OpenJoystickDriver-TESTER-BUILD.txt` (commit, version, build number, signing type, notarization result). The version is SemVer plus build metadata, such as `0.5.0-beta.5+build.1.14.89.sha.0123456789ab`.

## 4. Send the Build

Send the DMG unchanged with the [tester instructions](../testing/tester-builds.md). Testers attach the support report and the build text file to the issue. Controller-record tests also use [Test A Controller Record](../testing/controller-record.md).

## Failures

| Failure | Required action |
| --- | --- |
| The worktree is not clean. | Commit the exact test changes, then run the package command again. |
| A profile or entitlement does not match. | Run `just signing-configure`, then run `just signing-audit`. |
| Notarization credentials are missing. | Run `just release-notarize-store-credentials`. |
| Notarization fails. | Read the submission log with `just release-notarize-log <id>`. |
| Gatekeeper or stapling fails. | Do not send the DMG. Fix signing, then create a tester build again. |

Never skip the signing checks, and never change the app after notarization. Any change breaks the seal, and macOS stops trusting the app.
