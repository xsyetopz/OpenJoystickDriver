# PR #16: Fix Logitech F310 OUT endpoint (1 -> 2)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/16
- **State:** MERGED
- **Draft:** False
- **Author:** m-melaku
- **Created:** 2026-07-11T16:43:01Z
- **Updated:** 2026-07-12T05:47:35Z
- **Closed:** 2026-07-12T05:47:34Z
- **Merged:** 2026-07-12T05:47:34Z

## Description

Closes #15. Hardware only exposes endpoint 0x02 for OUT on this device; writes to 0x01 fail (LIBUSB_ERROR_NOT_FOUND per the issue's libusb trace). Matches the in:130/out:2 pairing already used by other profiles in this repo.

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Bug Fixes**
  * Improved Logitech Gamepad F310 controller communication by updating its USB output endpoint configuration.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Files

- `Sources/OpenJoystickDriverKit/Resources/Controllers/logitech-gamepad-f310.json` (+1/-1, MODIFIED)

## Commits

- `e93cc33d406d` Fix Logitech F310 OUT endpoint (1 -> 2)

## Conversation

### coderabbitai — 2026-07-11T16:43:17Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/16#issuecomment-4947802238)

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- review_stack_entry_start -->

[![Review Change Stack](https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui.svg)](https://app.coderabbit.ai/change-stack/xsyetopz/OpenJoystickDriver/pull/16?utm_source=github_walkthrough&utm_medium=github&utm_campaign=change_stack)

<!-- review_stack_entry_end -->
No actionable comments were generated in the recent review. 🎉

<details>
<summary>ℹ️ Recent review info</summary>

<details>
<summary>⚙️ Run configuration</summary>

**Configuration used**: Organization UI

**Review profile**: CHILL

**Plan**: Pro

**Run ID**: `c38f23a4-ca23-48ce-86aa-57c7979701dd`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between 852ad0452cef6e5593506a476e35e88d6056ad24 and e93cc33d406d14a93def46069f221accc0d44d0c.

</details>

<details>
<summary>📒 Files selected for processing (1)</summary>

* `Sources/OpenJoystickDriverKit/Resources/Controllers/logitech-gamepad-f310.json`

</details>

</details>

---
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

The Logitech F310 controller profile now declares USB OUT endpoint `2` instead of `1`; the IN endpoint and surrounding configuration remain unchanged.

### Changes

**F310 controller profile**

|Layer / File(s)|Summary|
|---|---|
|**Correct the USB OUT endpoint** <br> `Sources/OpenJoystickDriverKit/Resources/Controllers/logitech-gamepad-f310.json`|Updates the declared USB OUT endpoint from `1` to `2`.|

**Estimated code review effort:** 1 (Trivial) | ~2 minutes

**Poem**

> I’m a bunny with a gamepad bright,
> Now endpoint two sends packets right.
> The IN path stays, the profile’s neat,
> F310 hops to inputs’ beat.
> Carrot cheers for USB light!

</details>

<!-- walkthrough_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 5</summary>

<details>
<summary>✅ Passed checks (5 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                           |
| :------------------------: | :------- | :-------------------------------------------------------------------------------------------------------------------- |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.                                                           |
|         Title check        | ✅ Passed | The title is concise and accurately summarizes the Logitech F310 endpoint fix.                                        |
|     Linked Issues check    | ✅ Passed | The PR updates the Logitech F310 profile to use OUT endpoint 0x02, matching issue `#15`'s required fix.                 |
| Out of Scope Changes check | ✅ Passed | The only change is the F310 endpoint correction, which directly matches the linked issue and adds no unrelated scope. |
|     Docstring Coverage     | ✅ Passed | No functions found in the changed files to evaluate docstring coverage. Skipping docstring coverage check.            |

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

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=xsyetopz/OpenJoystickDriver&utm_content=16)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

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

### greptile-apps — COMMENTED

Submitted: 2026-07-11T16:43:08Z

Your trial has ended. [Reactivate Greptile](https://app.greptile.com/-/pull-requests) to resume code reviews.


## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-16.patch)
