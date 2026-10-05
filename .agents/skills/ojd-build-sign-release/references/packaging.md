# Packaging

## Contents

- [Version bump](#version-bump)
- [Tester DMG](#tester-dmg)
- [Release](#release)

## Version Bump

**Definition.** `./Scripts/ojd release bump-version <version>` sets the SemVer release version, without build metadata, in `Sources/OpenJoystickDriver/App/Info.plist` (`CFBundleShortVersionString`). That is the only file it edits, and every build script and the packaging scripts read the version from there. It needs no CHANGELOG heading, so bump at the start of a cycle: `just release-bump-version <version>`. `CFBundleVersion` is derived from the commit count, and is never set by hand.

**Use when.** Starting a new beta or release cycle, before its first tester build, so builds from the cycle never report the previous version.

**Do not use when.** Never use it to add build metadata. Provenance (`+build.<n>.sha.<commit>`) is computed at build time.

**Verify.** `Tests/RepositoryScripts/test_bump_version.py` passes. After the bump, `git diff` shows only version references.

## Tester DMG

**Definition.** Tester DMGs follow `docs/development/tester-builds.md`:

1. `just signing-install-profiles`
1. `just signing-configure`
1. `just package-tester-check`, which checks the environment and assets without building anything.
1. `just package-tester`

`just package-tester` builds the Developer ID app and DEXT. It then notarizes, staples, runs Gatekeeper, and writes `.build/tester-artifacts/OpenJoystickDriver-*-tester-*-macOS.dmg`, with `OpenJoystickDriver-TESTER-BUILD.txt` inside.

**Use when.** A tester needs an unpublished build.

**Do not use when.** The worktree is dirty, or only Apple Development signing is available.

**Cost removed.** A changed bundle after notarization has an invalid resource seal, and is not the tested artifact. Rebuild instead of patching.

**Verify.** The package command finishes its Gatekeeper and stapling checks. Notarization logs are available through `just release-notarize-log <id>`.

## Release

**Definition.** The GitHub release workflow (`.github/workflows/release.yml`) creates the tag, signs and notarizes, and uploads the DMG. The follow-up reconciliation is in `docs/development/releases.md`:

- run `just check` at the release commit;
- reconcile the generated notes with the contributions;
- read back the hosted release;
- close items only where the audit says the release is the closure gate.

**Use when.** Preparing or reconciling a release.

**Do not use when.** The user has not approved publication in this session. Publication, tags, and issue comments are public and cannot be recalled.

**Verify.** Verify each item in "Verify Before Closing Items" of `releases.md` against the hosted release.
