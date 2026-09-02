# PR #6: Prepare 0.2.0 release packaging

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/6
- **State:** MERGED
- **Draft:** False
- **Author:** xsyetopz
- **Created:** 2026-05-21T12:57:35Z
- **Updated:** 2026-05-21T12:59:31Z
- **Closed:** 2026-05-21T12:57:44Z
- **Merged:** 2026-05-21T12:57:44Z

## Description

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

## Release Notes

* **New Features**
  * Added update checking functionality. Users can now check for new releases and open the latest version directly from the application.

* **Chores**
  * Version updated to 0.2.0.
  * Release distribution format changed from ZIP to macOS DMG for improved installation experience.

<!-- review_stack_entry_start -->

[![Review Change Stack](https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui.svg)](https://app.coderabbit.ai/change-stack/xsyetopz/OpenJoystickDriver/pull/6?utm_source=github_walkthrough&utm_medium=github&utm_campaign=change_stack)

<!-- review_stack_entry_end -->

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Files

- `.github/workflows/release.yml` (+2/-2, MODIFIED)
- `CHANGELOG.md` (+11/-0, MODIFIED)
- `DriverKitExtension/Info.plist` (+1/-1, MODIFIED)
- `Sources/OpenJoystickDriver/App/AppModel.swift` (+19/-0, MODIFIED)
- `Sources/OpenJoystickDriver/App/UpdateChecker.swift` (+86/-0, ADDED)
- `Sources/OpenJoystickDriver/CLI.swift` (+2/-2, MODIFIED)
- `Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift` (+45/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Update/SemanticVersion.swift` (+129/-0, ADDED)
- `Tests/OpenJoystickDriverKitTests/SemanticVersionTests.swift` (+106/-0, ADDED)
- `scripts/README.md` (+6/-5, MODIFIED)
- `scripts/bump-version.sh` (+61/-9, MODIFIED)
- `scripts/ojd` (+1/-1, MODIFIED)
- `scripts/ojd-build.sh` (+2/-2, MODIFIED)
- `scripts/ojd-dmg-background.py` (+107/-0, ADDED)
- `scripts/ojd-package.sh` (+80/-5, MODIFIED)

## Commits

- `3918f8595eeb` Prepare 0.2.0 release packaging

## Conversation

### coderabbitai — 2026-05-21T12:57:49Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/6#issuecomment-4508474062)

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- This is an auto-generated comment: failure by coderabbit.ai -->

> [!CAUTION]
> ## Review failed
>
> The pull request is closed.

<!-- end of auto-generated comment: failure by coderabbit.ai -->

<details>
<summary>ℹ️ Recent review info</summary>

<details>
<summary>⚙️ Run configuration</summary>

**Configuration used**: Organization UI

**Review profile**: CHILL

**Plan**: Pro

**Run ID**: `ff4d1a33-db3a-42af-9607-24ad3730fb15`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between 5288024b112c2f1ffcc72234058ceff199ee3e59 and 3918f8595eeb24c026b733d70af14a5854a18265.

</details>

<details>
<summary>📒 Files selected for processing (15)</summary>

* `.github/workflows/release.yml`
* `CHANGELOG.md`
* `DriverKitExtension/Info.plist`
* `Sources/OpenJoystickDriver/App/AppModel.swift`
* `Sources/OpenJoystickDriver/App/UpdateChecker.swift`
* `Sources/OpenJoystickDriver/CLI.swift`
* `Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift`
* `Sources/OpenJoystickDriverKit/Update/SemanticVersion.swift`
* `Tests/OpenJoystickDriverKitTests/SemanticVersionTests.swift`
* `scripts/README.md`
* `scripts/bump-version.sh`
* `scripts/ojd`
* `scripts/ojd-build.sh`
* `scripts/ojd-dmg-background.py`
* `scripts/ojd-package.sh`

</details>

</details>

---
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

This release adds automatic update checking from GitHub alongside a packaging infrastructure overhaul switching from ZIP to DMG distribution. It bumps the version to 0.2.0 across all build artifacts and introduces SemanticVersion parsing for version comparison logic. The feature includes a new menu-bar UI section for checking updates and opening releases.

## Changes

**Version 0.2.0 Release with Update Checking and DMG Packaging**

| Layer / File(s) | Summary |
|---|---|
| **SemanticVersion parsing and comparison** <br> `Sources/OpenJoystickDriverKit/Update/SemanticVersion.swift`, `Tests/OpenJoystickDriverKitTests/SemanticVersionTests.swift` | `SemanticVersion` parses SemVer 2.0.0 strings (with optional leading `v`, prerelease, and build metadata) and implements `Comparable` ordering. Core version components (major/minor/patch) are compared numerically, then prerelease segments follow SemVer precedence rules: empty prerelease sorts higher than non-empty, numeric identifiers sort before non-numeric, and numeric identifiers use length-aware ordering. Comprehensive tests validate parsing, comparison, edge cases, and `nil` returns for invalid inputs. |
| **UpdateChecker service** <br> `Sources/OpenJoystickDriver/App/UpdateChecker.swift` | `UpdateChecker` fetches the latest GitHub release from `/repos/.../releases/latest`, decodes the JSON response (rejecting drafts), parses the tag as `SemanticVersion`, and compares it against the provided current version. Returns `UpdateCheckState.available(UpdateInfo)` when a newer version is found or `.upToDate` otherwise; network/parse/validation errors convert to `.failed`. A private async `data(for:)` helper bridges `URLSession.dataTask` to async/await. |
| **Update checking UI and AppModel integration** <br> `Sources/OpenJoystickDriver/App/AppModel.swift`, `Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift` | `AppModel` adds `@Published updateCheckState`, an `appVersion` property extracted from `Bundle.main`, and an `UpdateChecker` instance. The `start()` method launches an async `checkForUpdates()` task. `MenuBarPopoverView` now includes an "Updates" section with a check button; clicking shows conditional UI for idle, checking, up-to-date, available (with open-release action), and failed states. |
| **DMG background image generation** <br> `scripts/ojd-dmg-background.py` | New Python script deterministically generates a PNG background for DMG distribution. It defines a bitmap `FONT` for glyph-based text rendering, provides `chunk()` to build PNG chunks with CRC32 checksums, `in_text()` to rasterize characters, and `pixel()` to return RGB values by coordinate-based region checks. The `main()` function scans all pixels, compresses output with zlib, and writes a valid PNG file. |
| **Release packaging refactor from ZIP to DMG** <br> `scripts/ojd-package.sh` | `ojd-package.sh` replaces ZIP packaging with a full DMG creation flow. New helper functions detect and safely detach DMG mounts and clean up working directories. The packaging sequence stages the built `.app`, generates a background image via the new Python script, creates and mounts a read-write DMG, applies Finder view styling via embedded AppleScript, detaches, converts to a compressed DMG, and optionally codesigns (conditional on `CODESIGN_IDENTITY`). Final verification includes DMG validation and app signature re-verification. |
| **Version bump script and reference updates** <br> `scripts/bump-version.sh` | `bump-version.sh` discovers and updates additional files: `scripts/ojd-build.sh` (GUI and daemon bundle versions) and `DriverKitExtension/Info.plist` (DriverKit extension version). Changelog verification switches from regex to fixed-string `grep`. The embedded Python updater now accepts multiple file paths with distinct regex patterns for each, enforces minimum occurrence counts via `re.subn`, and exits with failure if any expected version reference is missing. |
| **Version string updates across codebase** <br> `scripts/ojd-build.sh`, `Sources/OpenJoystickDriver/CLI.swift`, `DriverKitExtension/Info.plist`, `scripts/ojd` | `CFBundleShortVersionString` is updated to `0.2.0` in the GUI app bundle, daemon bundle, and DriverKit extension. CLI `--version` and help output change to `v0.2.0`. The `ojd` script help text is updated to describe `package release` as producing a DMG. |
| **Release workflow and documentation updates** <br> `.github/workflows/release.yml`, `CHANGELOG.md`, `scripts/README.md` | GitHub Actions release workflow now publishes `*.dmg` instead of `*.zip` artifacts. `CHANGELOG.md` adds a `## 0.2.0` section documenting new Xbox 360 rumble support and DMG packaging (switching from zip-only distribution). `scripts/README.md` updates release packaging examples to show the `ojd package release 0.2.0` command and DMG output path, and GitHub Actions docs reference SemVer tags including `0.2.0` and DMG artifacts. |

## Estimated code review effort

🎯 3 (Moderate) | ⏱️ ~25 minutes

## Poem

> 🐰 A hop, a skip, to version new,
> With SemanticVersion logic true,
> Updates check from GitHub's nest,
> DMG-wrapped, our app looks best!
> Version bumped, the scripts align,
> Release day shines—0.2.0 divine! ✨

</details>

<!-- walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches</summary>

<details>
<summary>📝 Generate docstrings</summary>

- [ ] <!-- {"checkboxId": "7962f53c-55bc-4827-bfbf-6a18da830691"} --> Create stacked PR
- [ ] <!-- {"checkboxId": "3e1879ae-f29b-4d0d-8e06-d12b7ba33d98"} --> Commit on current branch

</details>
<details>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} -->   Create PR with unit tests
- [ ] <!-- {"checkboxId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} -->   Commit unit tests in branch `release-020-update-dmg`

</details>
<details>
<summary>✨ Simplify code</summary>

- [ ] <!-- {"checkboxId": "f120d606-b0e2-4b7d-8316-181794555b43", "radioGroupId": "simplify-output-choice-group-unknown_comment_id"} -->   Create PR with simplified code
- [ ] <!-- {"checkboxId": "9a4e3077-58f6-4eba-b7ee-62e936ea00ea", "radioGroupId": "simplify-output-choice-group-unknown_comment_id"} -->   Commit simplified code in branch `release-020-update-dmg`

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- This is an auto-generated comment: all tool run failures by coderabbit.ai -->

> [!WARNING]
> There were issues while running some tools. Please review the errors and either fix the tool's configuration or disable the tool if it's a critical failure.
>
> <details>
> <summary>🔧 OpenGrep (1.21.0)</summary>
>
> OpenGrep fatal error (exit code 2):
> ┌──────────────┐
> │ Opengrep CLI │
> └──────────────┘
>
> ^[[32m✔^[[39m ^[[1mOpengrep OSS^[[0m
>   ^[[32m✔^[[39m Basic security coverage for first-party code vulnerabilities.
>
> ^[[1m  Loading rules from local config...^[[0m
> [00.28][ERROR]: Error: exception Glob.Lexer.Syntax_error("malformed glob pattern: missing ']'")
> Raised at Glob__Lexer.syntax_error in file "libs/glob/Lexer.mll", line 8, characters 2-26
> Called from Glob__Lexer.__ocaml_lex_token_rec in file "libs/glob/Lexer.mll", line 29, characters 26-53
> Cal
>
>
>
> </details>

<!-- end of auto-generated comment: all tool run failures by coderabbit.ai -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=xsyetopz/OpenJoystickDriver&utm_content=6)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<sub>Comment `@coderabbitai help` to get the list of available commands and usage tips.</sub>

<!-- tips_end -->
<!-- internal state start -->


<!-- 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 -->

<!-- internal state end -->

## Reviews

_No reviews._

## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-6.patch)
