# Reconcile a GitHub Release

Use this procedure after the release commit and changelog are complete. The GitHub workflow creates the tag, signs and notarizes the app, uploads the DMG, and asks GitHub to generate release notes. Publication is a separate authorized action; do not infer permission to publish from this procedure.

## Versions

- The release version is SemVer 2.0.0 without build metadata. It lives in `CFBundleShortVersionString` of `Sources/OpenJoystickDriver/App/Info.plist` and in the tag, without a `v`. Set it with `./Scripts/ojd release bump-version <version>` (`just release-bump-version`) at the start of each cycle, before its first tester build. It needs no CHANGELOG heading.
- The app and the DriverKit extension share one `CFBundleVersion`, derived from the commit count (`1.14.89` for 1489 commits). It orders builds and follows the kext version grammar that DriverKit requires. Local DEXT installs append a development stage (`1.14.89d2`) so a rebuild of the same commit replaces the active extension.
- Provenance is SemVer build metadata, `+build.<number>.sha.<commit>`, with `.dirty` for an uncommitted tree. `--version`, the About panel, and tester build-info files show it. Build metadata never orders versions.

## Before Publication

1. Check out the exact release commit and run `just check`.
1. Confirm `git status --short` is empty and run `git diff --check`.
1. Generate or preview GitHub's release notes for the intended tag and previous tag.
1. Reconcile closed or unmerged contributions that are integrated in the release but omitted by GitHub. Confirm each contribution in source, tests, the changelog, or recorded hardware evidence.

## Reconcile the Body

Preserve GitHub's standard sections and order:

1. `What's Changed` lists each credited item, author, and hosted link.
1. `New Contributors` lists only accounts making their first credited contribution. Check earlier releases before adding an account.
1. `Full Changelog` compares the previous release tag with the new tag.

Use a UTF-8 body file rather than shell interpolation. Read the hosted release back immediately after editing and compare every line with the intended body.

## Verify Before Closing Items

Verify all of these against the hosted release:

- the tag resolves to the intended commit;
- the release is published, not a draft;
- a prerelease tag is marked as a prerelease;
- the expected DMG exists and its asset state is uploaded;
- the complete body contains the contribution and contributor links;
- the Full Changelog range starts at the previous release and ends at the new release.

Only then post item-specific comments describing the implemented behavior and the remaining hardware procedure. Close issues or unmerged pull requests only when their audit classification says the published release is the closure gate. Leave hardware-confirmation items open.
