# Tasks: Noncommercial License

Each task names its check. Changing `LICENSE`, enabling the CLA workflow and contacting contributors are publication steps: each one waits for the maintainer's go-ahead.

## 1. Decisions before Any File Changes

- [ ] 1.1 The maintainer has a lawyer review `design.md` D3, D4 and D5 and the drafts of `CLA.md` and `COMMERCIAL.md`. Verify: the maintainer records the outcome in this task; release 0.6.0-alpha.2 waits for it.
- [x] 1.2 The maintainer picks the contact for commercial licenses (design Open Question 1). Verify: the contact is written into `COMMERCIAL.md` in task 3.2. Done: the commercial tier on GitHub Sponsors, written into `COMMERCIAL.md`.

## 2. Checks First

- [x] 2.1 Add `Scripts/Quality/check_license_headers.py` (design D6) and a Python test with three fixtures: a GPL SPDX line under `Sources`, "GNU General Public License" text under `Scripts`, and a GPL reference under `docs/` that must pass. Verify: the test fails before the script exists and passes after it; `./Scripts/ojd` Python test route. Done: `Tests/RepositoryScripts/test_license_headers.py`, 4 tests pass.
- [x] 2.2 Add a license-text check: the pinned PolyForm Noncommercial 1.0.0 text (`Resources/Licenses/polyform-noncommercial-1.0.0.txt`, with its SHA-256 recorded) against `LICENSE` without the `Required Notice:` line. Verify: a test fails on a one-word edit and passes on the verbatim text. Done: `Scripts/Quality/check_license_text.py` and `test_license_text.py`; 6 tests pass, the one-word edit fails at line 7.
- [x] 2.3 Wire both checks into `just check`. Verify: `just check` runs them, and the license-text check fails while `LICENSE` is still MIT. Done: `just check-fast`, `ci.yml` and `release.yml` run both; the text check failed on MIT. The header check fails on `RecordedHIDDescriptors.swift` until 4.4.

## 3. License Files

- [x] 3.1 Replace `LICENSE` with the fetched PolyForm text and the `Required Notice:` line (design D1). Verify: the check from 2.2 passes. Done: the text check passes.
- [x] 3.2 Write `COMMERCIAL.md` (design D2) and `CLA.md` (design D3) from the reviewed drafts. Verify: markdownlint passes; each file states what the spec requires. Done: drafts written; markdownlint passes. The lawyer review stays in 1.1.
- [x] 3.3 Update `README.md`: the License section, the static badge, and the sponsorship paragraph addressed to commercial users. Verify: markdownlint; the section names both licenses and links `COMMERCIAL.md`. Done: markdownlint passes.
- [x] 3.4 Add the License section to `CONTRIBUTING.md` (CLA and the source rule), and a CLA checkbox to `.github/pull_request_template.md`. Verify: markdownlint. Done: markdownlint passes.
- [x] 3.5 Add `NSHumanReadableCopyright` to the app's Info.plist; the line holds only names and a version, so it is not localized. Verify: the Info.plist of a built app has the key; the About panel shows the line. Done: the plist has the key, and the dev app's About panel lists `© 2026 Krystian J. PolyForm Noncommercial 1.0.0.` as static text (`Scripts/GUI/ax.js labels`).

## 4. Contributors and Notices

- [ ] 4.1 The maintainer asks the five outside contributors (design D4) to sign the CLA for their commit. Verify: each answer is recorded in this task.
- [ ] 4.2 For each contributor who does not sign, add an entry with the commit and the MIT text to `THIRD_PARTY_NOTICES.md`. Verify: `git diff --check`; the entry names the commit hash.
- [x] 4.3 Check that every adapted or linked third-party source in the tree has its notice. Verify: `grep -rn "adapted from\|Copyright" Sources Tools` lists only sources that `THIRD_PARTY_NOTICES.md` names. Done: the grep lists only `MotionProjection.swift` (GamepadMotionHelpers, in the notices). swift-argument-parser is Apache-2.0 with the Runtime Library Exception, which waives attribution for compiled code; SwifterKit is the maintainer's own.
- [ ] 4.4 Replace the four descriptors in `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Generic/RecordedHIDDescriptors.swift` (Xbox One S Linux and Windows modes, Xbox Series, GameSir G7 SE) with captures from testers' controllers, each named by its source in the doc comment. Verify: `swift test --filter ZRzBrakeLeftLayoutTests` and `--filter XboxBluetoothDescriptorLayoutTests` pass, and the check from 2.1 passes on `Tests`. Open until the captures arrive; release 0.6.0-alpha.2 waits for it.

## 5. CLA Workflow

- [ ] 5.1 Add the `contributor-assistant/github-action` workflow, pinned by commit SHA, with the signature file on a separate branch and an allow list for the maintainer and bots (design D3). Verify: `actionlint` passes; a test PR from an unsigned account fails the check, and after signing it passes. Progress: `.github/workflows/cla.yml` pins v2.6.1 (`ca4a40a`) with signatures on the `cla-signatures` branch; actionlint passes. The test PR waits for the maintainer.

## 6. Release Notes

- [x] 6.1 Add a `### Changed` entry to `CHANGELOG.md` `[Unreleased]`: the license is PolyForm Noncommercial 1.0.0 from this release on, commercial use needs a license, and releases up to 0.6.0-alpha.1 stay MIT. Verify: markdownlint. Done: markdownlint passes.
- [ ] 6.2 Run `just check` once. Verify: exit 0.
