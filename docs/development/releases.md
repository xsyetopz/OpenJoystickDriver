# Check and Fix a GitHub Release

How to publish a new version of OJD. Run these steps once the release commit and changelog are done. The GitHub workflow tags, signs, notarizes, uploads the DMG, and writes release notes. Publishing needs its own go-ahead.

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

The app and extension share one `CFBundleVersion`, made from the number of commits (1.14.89 for 1489 commits) in the format macOS uses for kernel extension versions. Local DEXT installs add a development stage (1.14.89d2), so rebuilding the same commit still replaces the running extension.

A tester build is a pre-release.

| Preceding release | Tester tag |
| --- | --- |
| A prerelease | `<prerelease tag>.tester.N` (0.6.0-alpha.2.tester.1) |
| `X.Y.(Z-1)` | `X.Y.Z-tester.N`, Z of 1 or more |

The workflow refuses a tester tag when the release before it isn't a tag. `python3 -m Scripts.Release.bundle_version --tag-kind <tag>` and `--tester-base <tag>` print the kind and the release.

Where a build came from is written as build metadata, `+build.<number>.sha.<commit>`, plus .dirty when the tree had uncommitted changes. `--version`, the About panel, and tester build-info files show it. It never decides which version is newer.

## Before Publishing

1. Check out the release commit and run `just verify`.
2. Confirm `git status --short` is empty; run `git diff --check`.
3. Preview GitHub's release notes for the tag and the previous tag.
4. Find contributions in the release that GitHub left out. Confirm each one in source, tests, the changelog, or hardware results.

## Fix the Release Notes

Keep GitHub's section order:

- What's Changed: each credited item, its author, and a link.
- New Contributors: only people credited for the first time. Check earlier releases.
- Full Changelog: the previous release tag compared with this one.

Write the notes to a UTF-8 file so the shell can't change any text. After the edit, read the published release back and compare every line.

## Check Before Closing Issues

On the published release, check that:

- The tag resolves to the release commit.
- It's published, not a draft, and a prerelease tag is marked as a prerelease.
- The DMG is uploaded.
- The body has the contribution and contributor links.
- Full Changelog runs from the previous release to this one.

Comment on each issue with what the release does and what hardware testing is left. Close an issue only when publishing the release is the last thing it was waiting for. Leave issues that still need someone to test on hardware open.
