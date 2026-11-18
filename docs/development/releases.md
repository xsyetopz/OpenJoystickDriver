# Reconcile a GitHub Release

Run after the release commit and changelog are complete. The GitHub workflow tags, signs, notarizes, uploads the DMG, and generates release notes. Publishing needs separate authorization.

## Versions

The release version is SemVer 2.0.0 without build metadata, in `CFBundleShortVersionString` of `Sources/OpenJoystickDriver/App/Info.plist` and in the tag (no `v`).

Run `just release-bump-version <part>` before a cycle's first build.

| Part | Effect |
| --- | --- |
| `major`, `minor`, `patch` | raises that number, drops the prerelease |
| `prerelease` | raises N (0.6.0-alpha.3 to 0.6.0-alpha.4) |
| `alpha`, `beta`, `rc` | moves to that stage's .1, after the next patch when the current version is a release |
| `release` | drops the prerelease |

`just release-bump-version <version>` sets an exact version. The build copies it into every bundle and the extension, so `Info.plist` is the only file to change; no CHANGELOG heading needed.

The app and extension share one `CFBundleVersion`, from the commit count (1.14.89 for 1489 commits), in the kext version grammar. Local DEXT installs append a development stage (1.14.89d2), so a rebuild of one commit replaces the active extension.

A tester build is a pre-release.

| Preceding release | Tester tag |
| --- | --- |
| A prerelease | `<prerelease tag>.tester.N` (0.6.0-alpha.2.tester.1) |
| `X.Y.(Z-1)` | `X.Y.Z-tester.N`, Z of 1 or more |

The workflow refuses a tester tag whose preceding release is not a tag. `python3 -m Scripts.Release.bundle_version --tag-kind <tag>` and `--tester-base <tag>` print the kind and the release.

Provenance is build metadata, `+build.<number>.sha.<commit>`, with .dirty for an uncommitted tree. `--version`, the About panel, and tester build-info files show it; it never orders versions.

## Before Publication

1. Check out the release commit and run `just verify`.
2. Confirm `git status --short` is empty; run `git diff --check`.
3. Preview GitHub's release notes for the tag and the previous tag.
4. Find contributions the release includes and GitHub omits; confirm each in source, tests, the changelog, or hardware evidence.

## Reconcile the Body

Keep GitHub's section order: What's Changed (each credited item, author, link), New Contributors (only first-time credited accounts; check earlier releases), Full Changelog (previous release tag compared with this one).

Write the body to a UTF-8 file with no shell interpolation; after the edit, read the hosted release back and compare every line.

## Verify Before Closing Items

Hosted release:

- The tag resolves to the release commit.
- Published, not a draft; a prerelease tag is marked as a prerelease.
- The DMG is uploaded.
- The body has the contribution and contributor links.
- Full Changelog runs from the previous release to this one.

Comment on each item with the implemented behavior and remaining hardware procedure. Close an item only when its audit classification makes the published release the closure gate; leave hardware-confirmation items open.
