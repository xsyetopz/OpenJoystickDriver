# PR #20: fix(controllers): send GIP rumble frames without the internal option flag

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/20
- **State:** MERGED
- **Draft:** False
- **Author:** cooltune
- **Created:** 2026-07-22T10:05:53Z
- **Updated:** 2026-07-22T17:19:24Z
- **Closed:** 2026-07-22T17:19:24Z
- **Merged:** 2026-07-22T17:19:24Z

## Description

## Summary

Physical rumble on GIP (Xbox One) controllers never fires: `GIPParser.sendRumble` stamps the frame's options byte with `GIPOption.internal` (0x20), and the controller silently discards such rumble frames. Setting the options byte to 0x00 — matching the unflagged rumble commands the Linux xone/xpad drivers send — makes rumble work immediately.

One functional byte changed; also adds a changelog entry under 0.5.0-alpha.5.

## Hardware verification (model 1537, 045E:02D1, USB, macOS 26 / Apple Silicon)

Follow-up to the hardware testing in #18, using current `main` built from source:

- With the options byte 0x20 (current main): `--headless physical-output rumble` reports success but the pad never rumbles, including while provably awake (live input streaming in `--headless input watch` during the send). Four timed bursts at full intensity: nothing.
- With the options byte 0x00: all four motors respond — left main, right main, and both trigger actuators, confirmed individually per the `physical-output plan` sequence.
- A/B isolation: reverting only the duration byte while keeping options=0x00 still rumbles (short burst, as duration=32 implies) — the duration byte was never the problem.
- The 0x20 flag is not broadly rejected by this pad: LED (0x0a) and auth (0x06) frames flagged 0x20 are honored (same frames used in the #18 hardware report). The discard is specific to rumble (0x09).

Possibly worth a look separately: `keepAlive` (CMD 0x03) also sends `GIPOption.internal`. No observable harm on a wired 1537 — it runs for hours with no host→pad keep-alives at all and emits its own 0x03 frames to the host — but wireless-adapter scenarios may differ.

## Testing

- `swift build` clean
- `./scripts/ojd test parsers-macos14` → PASS (`swift test` unavailable here: CommandLineTools-only toolchain lacks Swift Testing)
- Hardware verification as above

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Bug Fixes**
  * Fixed rumble feedback for Xbox One controllers by ensuring rumble commands are accepted correctly.
  * Confirmed physical rumble functionality on verified Xbox One hardware.
* **Documentation**
  * Updated the changelog with details about the Xbox One rumble fix.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Files

- `CHANGELOG.md` (+3/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift` (+4/-1, MODIFIED)

## Commits

- `2f9f0d016617` fix(controllers): send GIP rumble frames without the internal option …

## Conversation

### coderabbitai — 2026-07-22T10:06:10Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/20#issuecomment-5044527015)

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- review_stack_entry_start -->

[![Review Change Stack](https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui.svg)](https://app.coderabbit.ai/change-stack/xsyetopz/OpenJoystickDriver/pull/20?utm_source=github_walkthrough&utm_medium=github&utm_campaign=change_stack)

<!-- review_stack_entry_end -->
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

The GIP rumble command now clears its internal options flag by sending `0x00`. The changelog documents the Xbox One controller fix and hardware verification for `045E:02D1`.

### Changes

**GIP rumble fix**

|Layer / File(s)|Summary|
|---|---|
|**Clear GIP rumble options flag** <br> `Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift`, `CHANGELOG.md`|`sendRumble` now sends `0x00` as the packet options byte, with explanatory comments and a changelog entry describing the Xbox One fix and hardware verification.|

**Estimated code review effort:** 1 (Trivial) | ~5 minutes

**Suggested reviewers:** `xsyetopz`

**Poem**

> I’m a rabbit hopping light,
> Rumble frames now work just right.
> The hidden flag has gone away,
> Xbox pads can thump and play.
> `0x00` makes joy awake!

</details>

<!-- walkthrough_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 5</summary>

<details>
<summary>✅ Passed checks (5 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                |
| :------------------------: | :------- | :--------------------------------------------------------------------------------------------------------- |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.                                                |
|         Title check        | ✅ Passed | The title clearly summarizes the main fix: GIP rumble frames now omit the internal option flag.            |
|     Docstring Coverage     | ✅ Passed | No functions found in the changed files to evaluate docstring coverage. Skipping docstring coverage check. |
|     Linked Issues check    | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                   |
| Out of Scope Changes check | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                   |

</details>

</details>

<!-- pre_merge_checks_walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches</summary>

<details>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} -->   Create PR with unit tests

</details>
<details>
<summary>✨ Simplify code</summary>

- [ ] <!-- {"checkboxId": "f120d606-b0e2-4b7d-8316-181794555b43", "radioGroupId": "simplify-output-choice-group-unknown_comment_id"} -->   Create PR with simplified code

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=xsyetopz/OpenJoystickDriver&utm_content=20)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<sub>Comment `@coderabbitai help` to get the list of available commands.</sub>

<!-- tips_end -->

## Reviews

### coderabbitai — COMMENTED

Submitted: 2026-07-22T10:08:23Z

<details>
<summary>🧹 Nitpick comments (1)</summary><blockquote>

<details>
<summary>Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift (1)</summary><blockquote>

`161-166`: _🎯 Functional Correctness_ | _🔵 Trivial_ | _⚡ Quick win_

**Add or confirm a packet-level regression test for the cleared options byte.**

This hardware-specific fix should assert that `sendRumble` serializes byte 1 as `0x00`; otherwise a future refactor could restore `GIPOption.internal` while existing parser tests remain green. Also confirm the required focused Swift and runtime diagnostics.

As per coding guidelines, Swift changes require `rtk test swift test`, focused touched-surface validation, and compact backend, GameController, and SDL3 diagnostics.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift` around lines 161
- 166, The sendRumble packet serialization must have a packet-level regression
test asserting byte 1 is 0x00, preventing restoration of GIPOption.internal. Add
or update the focused GIPParser test for sendRumble to inspect the serialized
packet while preserving existing rumble fields, then run rtk test swift test,
focused touched-surface validation, and the required compact backend,
GameController, and SDL3 diagnostics.
```

</details>

<!-- cr-comment:v1:41deebd87644e360fbd986ad -->

_Source: Coding guidelines_

</blockquote></details>

</blockquote></details>

<details>
<summary>🤖 Prompt for all review comments with AI agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

Nitpick comments:
In `@Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift`:
- Around line 161-166: The sendRumble packet serialization must have a
packet-level regression test asserting byte 1 is 0x00, preventing restoration of
GIPOption.internal. Add or update the focused GIPParser test for sendRumble to
inspect the serialized packet while preserving existing rumble fields, then run
rtk test swift test, focused touched-surface validation, and the required
compact backend, GameController, and SDL3 diagnostics.
```

</details>

---

<details>
<summary>ℹ️ Review info</summary>

<details>
<summary>⚙️ Run configuration</summary>

**Configuration used**: Organization UI

**Review profile**: CHILL

**Plan**: Pro

**Run ID**: `7f6a9be7-523d-45bc-87c3-ed25f22be20c`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between 6ea7e80218991077a7b5f37861cf8d62ab66524c and 2f9f0d01661715c5767b29b86ba1e70436e1d3be.

</details>

<details>
<summary>📒 Files selected for processing (2)</summary>

* `CHANGELOG.md`
* `Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift`

</details>

</details>

<!-- This is an auto-generated comment by CodeRabbit for review status -->


## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-20.patch)
