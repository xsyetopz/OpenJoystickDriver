---
name: ojd-build-sign-release
description: >-
  Builds, installs, signs, and packages OpenJoystickDriver: the app bundle and
  the XboxUSBDevice DriverKit extension through ./Scripts/ojd build, signing
  profiles and entitlement doctor checks, stale-DEXT repair, version bumps,
  Developer ID tester DMGs, notarization, and release reconciliation. Use when
  a local install fails, an entitlement or profile mismatch appears, the
  system extension does not activate, or a tester or release build is needed.
  Not for build scripts or CI themselves (ojd-repo-tooling) or controller
  probes (ojd-hardware-evidence).
---

# OpenJoystickDriver Build, Sign, and Release

Produce a signed app (and DEXT when needed) from the exact intended commit, and diagnose signing from its evidence instead of editing profiles or entitlements until the error stops.

## Workflow

1. Read `contributing/development/signing.md`. For packaging, also read `contributing/development/tester-builds.md` or `contributing/development/releases.md`.
1. Pick the [build route](references/build-and-install.md#build-routes). A DEXT change needs `build install dev`. An app-only change can use `build install-fast dev`.
1. Ask the user before any install. It replaces `/Applications/OpenJoystickDriver.app` and can prompt for system extension approval.
1. On a signing failure, follow the [signing diagnosis](references/signing.md#signing-diagnosis) order.
1. After installing, check the result with:

   ```bash
   ojd diagnose
   ./Scripts/ojd diagnose dext
   ```

1. For a version bump, a tester DMG, or a release, follow [packaging](references/packaging.md). Ask before notarizing, and before any publication.

## Route the problem to a card

| Situation | Card |
| --- | --- |
| Which build command | [Build routes](references/build-and-install.md#build-routes) |
| Old DEXT still running after upgrade | [Stale DEXT](references/build-and-install.md#stale-dext) |
| `swift build` fails with a module-cache mismatch | [Module cache](references/build-and-install.md#module-cache) |
| Entitlement, profile, or identity mismatch | [Signing diagnosis](references/signing.md#signing-diagnosis) |
| Virtual HID device creation fails on a dev build | [Signing diagnosis](references/signing.md#signing-diagnosis) (device list) |
| Changing the release version | [Version bump](references/packaging.md#version-bump) |
| DMG for testers | [Tester DMG](references/packaging.md#tester-dmg) |
| Publishing or reconciling a release | [Release](references/packaging.md#release) |

## Rules

- Never edit a provisioning profile or broaden an entitlement to silence a mismatch. DriverKit entitlements are Apple-issued data. The fix is a matching profile, or an exact entitlement plist.
- Do not edit generated DriverKit files in `.build/driverkit/generated/`. Regenerate them with `./Scripts/ojd driverkit generate`. The authored DEXT entitlements are in `Sources/DriverKitGenerator/Entitlements/XboxUSBDevice.entitlements`.
- Keep `.env.dev`, `.env.release`, certificates, profiles, Team IDs, and notarization credentials out of commits, logs, and reports.
- Apple Development builds run only on registered Macs, so never send them to testers.
- Package only from a clean worktree at the commit under test. The DMG metadata names that commit.
- Publishing a release, pushing a tag, and posting to issues are public actions. Each needs explicit user approval in this session.

## References

- [Build and install](references/build-and-install.md): build routes, stale DEXT, module cache.
- [Signing](references/signing.md): signing diagnosis, entitlement shape.
- [Packaging](references/packaging.md): version bump, tester DMG, release.

## Completion evidence

The report gives the command run, the commit, and the version with build metadata. It includes the `signing doctor` result and the `diagnose report` / `diagnose dext` summary, plus the DMG path when packaging. It lists the user approvals obtained, and what remains unverified (for example Gatekeeper on another Mac, or macOS 12).
