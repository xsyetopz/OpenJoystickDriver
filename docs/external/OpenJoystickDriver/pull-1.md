# PR #1: Add Flydigi Vader 5S support with per-device endpoint config

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/1
- **State:** MERGED
- **Draft:** False
- **Author:** danilowanner
- **Created:** 2026-05-04T14:16:31Z
- **Updated:** 2026-05-05T01:34:57Z
- **Closed:** 2026-05-05T01:34:57Z
- **Merged:** 2026-05-05T01:34:57Z

## Description

Hi!

First of all thanks for this project!

**TL;DR:
I don't have an Apple Developer account and cannot make a build to fully test my changes. I did run the daemon ad-hoc, detected and matched by VID:PID; GIP init sequence completes 👉 Xbox button lights up. I used Claude to implement the code changes.**

I bought a new Flydigi Vader 5S controller, official Xbox licensed (USB only), but found it does not work for cloud gaming through my Mac. I was curious if I could find a solution to it.

It speaks standard GIP, but with two quirks that prevented it from working with the existing daemon:

- **Wrong endpoints.** The GIP parser and auth handler had `0x02`/`0x82` hardcoded. The Vader 5S uses endpoint `0x01` OUT and `0x81` IN. All init packets were going to the right place, but input reports were being read from the wrong endpoint (0 bytes, every poll).
- **Unconfigured on plug.** After a fresh plug the controller enumerates with no active USB configuration. Calling `claimInterface(0)` on a configuration-0 device returns `LIBUSB_ERROR_OTHER` and GIP init packets sent before `setConfiguration(1)` are silently ignored 👉  the Xbox button never lights up.

### What changed

- `devices.json` new Vader 5S entry with `input_endpoint: 129`, `output_endpoint: 1`, and `needs_set_configuration: true`
- `USBEndpointConfig` struct added to `DeviceCatalog` 👉 carries both endpoint addresses and the `needsSetConfiguration` flag, resolved per VID:PID at pipeline startup
- `GIPParser` + `GIPAuthHandler` 👉 output endpoint now injected at construction (was hardcoded `0x02`)
- `DevicePipeline` 👉 `setConfiguration(1)` gated behind the catalog flag (safe for all existing devices); IN endpoint driven by `USBEndpointConfig`; 200 ms post-handshake settle constant added
- `README` 👉 Vader 5S in the feature table; new `devices.json` USB quirk fields documented

### What I verified

Running the daemon ad-hoc (unsigned, `swift build` + direct launch):
- Controller is detected and matched by VID:PID
- GIP init sequence completes 👉 Xbox button lights up
- Input loop starts on the correct endpoint (`0x81`)

### What I could not verify

Virtual HID output requires the `com.apple.developer.hid.virtual.device` entitlement, which is only honoured on Developer ID-signed binaries. I don't currently have an Apple Developer account, so I was unable to confirm that controller input flows through to games end-to-end.

Disclaimer: I am a software engineer, but this is out of my expertise and coded with Claude Opus 4.7.

I really like the project and am keen to get my new gadget onboard. If you could help me with a build an retesting existing controllers that would be great 💯

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **New Features**
  * Added support for Flydigi Vader 5S controller with specialized endpoint configuration.
  * Implemented configurable USB endpoint settings to accommodate controllers with non-standard requirements.

* **Documentation**
  * Updated controller support guide with optional USB endpoint configuration fields.
  * Enhanced Xbox One/Series controller verification details and authentication notes.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Files

- `README.md` (+12/-1, MODIFIED)
- `Sources/OpenJoystickDriverKit/Device/DeviceManager.swift` (+3/-1, MODIFIED)
- `Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift` (+18/-4, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift` (+35/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/GIPAuthHandler.swift` (+5/-1, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/GIPParser.swift` (+9/-5, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/ParserRegistry.swift` (+7/-1, MODIFIED)
- `Sources/OpenJoystickDriverKit/Resources/devices.json` (+12/-0, MODIFIED)

## Commits

- `3c6736d2937d` feat(gip): add Flydigi Vader 5S support with per-device endpoint config

## Conversation

### coderabbitai — 2026-05-04T14:16:44Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/1#issuecomment-4371777376)

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

A new USB endpoint configuration system allows per-device customization of input/output endpoints and optional USB configuration setup. The `USBEndpointConfig` type is defined, loaded from `devices.json`, threaded through the parser registry and device manager, and consumed by the pipeline and GIP authentication handler during initialization and I/O operations.

## Changes

**USB Endpoint Configuration Support**

|Layer / File(s)|Summary|
|---|---|
|**Data Shape** <br> `Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift`|New public `USBEndpointConfig` struct defines `inputEndpoint`, `outputEndpoint`, and `needsSetConfiguration` with a `gipDefault` fallback.|
|**Catalog Loading** <br> `Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift`|`DeviceCatalog` loads per-device endpoint overrides from `devices.json` into an `endpointEntries` map and adds `endpointConfig(for:)` lookup method.|
|**Parser Instantiation** <br> `Sources/OpenJoystickDriverKit/Protocol/GIPParser.swift`, `Sources/OpenJoystickDriverKit/Protocol/GIPAuthHandler.swift`|`GIPParser` and `GIPAuthHandler` accept `USBEndpointConfig` and `outEndpoint` parameters during initialization instead of using hardcoded defaults.|
|**Registry Exposure** <br> `Sources/OpenJoystickDriverKit/Protocol/ParserRegistry.swift`|`ParserRegistry.parser(for:)` queries catalog for endpoint config and passes it to `GIPParser`; new `endpointConfig(for:)` method exposes the lookup.|
|**Device Manager Wiring** <br> `Sources/OpenJoystickDriverKit/Device/DeviceManager.swift`|`DeviceManager` retrieves endpoint config from parser registry and supplies it to `DevicePipeline` during USB pipeline construction.|
|**Pipeline Implementation** <br> `Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift`|`DevicePipeline` accepts `endpointConfig`, conditionally calls `setConfiguration(1)`, derives input endpoint from config, and adds a 200ms post-handshake settling delay before first USB IN read.|
|**Data Source** <br> `Sources/OpenJoystickDriverKit/Resources/devices.json`|Flydigi Vader 5S device entry added with vendor/product IDs and endpoint/configuration quirk fields (`input_endpoint`, `output_endpoint`, `needs_set_configuration`).|
|**Documentation** <br> `README.md`|Updated "What works" table with hardware verification notes and GIP authentication clarification; "Adding controller support" section documented the three new optional `devices.json` fields and the rule that input/output endpoints must both be present together.|

## Estimated code review effort

🎯 3 (Moderate) | ⏱️ ~30 minutes

## Poem

> 🐰 *Endpoints now dance to their device's own tune,*
> *Configuration flows from JSON noon,*
> *Controllers wake gently with settling grace—*
> *Each quirk has found its rightful place!*
> *Flexibility hops through the pipeline's domain.* 🎮✨

</details>

<!-- walkthrough_end -->

<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 4 | ❌ 1</summary>

### ❌ Failed checks (1 warning)

|     Check name     | Status     | Explanation                                                                           | Resolution                                                                         |
| :----------------: | :--------- | :------------------------------------------------------------------------------------ | :--------------------------------------------------------------------------------- |
| Docstring Coverage | ⚠️ Warning | Docstring coverage is 50.00% which is insufficient. The required threshold is 80.00%. | Write docstrings for the functions missing them to satisfy the coverage threshold. |

<details>
<summary>✅ Passed checks (4 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                                                                                        |
| :------------------------: | :------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.                                                                                                                        |
|         Title check        | ✅ Passed | The title accurately and concisely describes the main change: adding support for a specific controller (Flydigi Vader 5S) while introducing per-device USB endpoint configuration. |
|     Linked Issues check    | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                                                           |
| Out of Scope Changes check | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                                                           |

</details>

<sub>✏️ Tip: You can configure your own custom pre-merge checks in the settings.</sub>

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

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=xsyetopz/OpenJoystickDriver&utm_content=1)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>
<!-- review_rate_limit_status_start -->
<sub>Review rate limit: 0/1 reviews remaining, refill in 60 minutes.</sub>
<!-- review_rate_limit_status_end -->

<sub>Comment `@coderabbitai help` to get the list of available commands and usage tips.</sub>

<!-- tips_end -->

<!-- internal state start -->


<!-- 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 -->

<!-- internal state end -->

### xsyetopz — 2026-05-04T15:53:08Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/1#issuecomment-4372478076)

Hello! Whether it's an AI agent speaking on behalf of a human operator, or the human operator itself, I can disclose a few things:

1. I've yet to go thru the entire application and redo almost everything, because even in my own testing on GameSir G7 SE, there are major setbacks preventing the controllers from being recognised in applications like PCSX2, but work normally thru Gamepad API on browsers if you spoof themselves as specific protocol devices, like the G7 SE as an Xbox One wireless controller.

I've yet to figure out a proper long-term, user-contributable solution to this problem. I unfortunately don't have standard GIP/Xinput or DS3/4-based controllers at hand for testing. While I do own a standard Xbox 360 controller, I don't have a supporting wired cable for it.

### danilowanner — 2026-05-05T01:26:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/1#issuecomment-4375868508)

Understood. Thanks for the update.
Hopefully we can figure out how to work around the current limitations.

I would be happy to test with my wired Vader 5s if you could send me a build of my PR's version. My main blocker is the lack of Apple developer account which would set me back 99 USD, a bit expensive for a test. I am assuming you have one to do the signed builds?

My goal is compatibility with GeForce Now, Xbox Cloud, AirGPU (Parsec/Moonlight) Mac clients. They all use Apple GameController.framework (GCController) as far as my research goes.

### xsyetopz — 2026-05-05T01:33:37Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/1#issuecomment-4375891147)

That's interesting!. I'd first take your comment && research, then look into architectural changes for long-term, && only after that I should consider the "backends," such as GCController, GCVirtualController, IOHID/IOUSB, && other forms. It really does get complex. If you find any information to how apps like PCSX2 work, && a native controller to test on PCSX2 instead of 3rd party, PLEASE LET ME KNOW! It would be extremely useful.

## Reviews

### coderabbitai — COMMENTED

Submitted: 2026-05-04T14:20:07Z

<details>
<summary>🧹 Nitpick comments (3)</summary><blockquote>

<details>
<summary>Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift (2)</summary><blockquote>

`38-42`: _⚡ Quick win_

**Validate endpoint values before UInt8 conversion.**

The `inputEndpoint` and `outputEndpoint` are decoded as `Int` from JSON and directly converted to `UInt8` without bounds checking. While USB endpoint addresses are always ≤255, malformed JSON could cause silent truncation.



<details>
<summary>♻️ Proposed fix to add bounds validation</summary>

```diff
         if let inEP = entry.inputEndpoint, let outEP = entry.outputEndpoint {
+          guard (0...255).contains(inEP), (0...255).contains(outEP) else {
+            print("[DeviceCatalog] Invalid endpoint values for \(key): in=\(inEP) out=\(outEP)")
+            continue
+          }
           endpoints[key] = USBEndpointConfig(
             inputEndpoint: UInt8(inEP), outputEndpoint: UInt8(outEP),
             needsSetConfiguration: entry.needsSetConfiguration ?? false)
         }
```
</details>

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against the current code and only fix it if needed.

In `@Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift` around lines 38 -
42, The code directly casts entry.inputEndpoint and entry.outputEndpoint
(decoded as Int) to UInt8 when constructing USBEndpointConfig in the endpoints
assignment; add explicit bounds checking (0...255) for both inputEndpoint and
outputEndpoint before converting to UInt8 (e.g., guard or if-let that ensures
values are within range) and handle out-of-range or nil values by skipping this
entry or logging an error instead of silently truncating; update the logic
around endpoints[key] = USBEndpointConfig(...) and the use of
entry.needsSetConfiguration to only run when validated UInt8 values are
available.
```

</details>

---

`11-12`: _💤 Low value_

**Optional: Use `Self` for static reference.**

SwiftLint suggests using `Self` instead of `USBEndpointConfig` in static property definitions for consistency.



<details>
<summary>♻️ Proposed fix</summary>

```diff
-  public static let gipDefault = USBEndpointConfig(
+  public static let gipDefault = Self(
     inputEndpoint: 0x82, outputEndpoint: 0x02, needsSetConfiguration: false)
```
</details>

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against the current code and only fix it if needed.

In `@Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift` around lines 11 -
12, The static property gipDefault currently constructs a USBEndpointConfig
directly; replace that explicit type with a static/self reference to satisfy
SwiftLint (use Self or .init) so the declaration becomes a Self-based
initializer for USBEndpointConfig; update the expression that creates the
instance (referencing gipDefault and USBEndpointConfig) to use Self(...) or
.init(...) instead of USBEndpointConfig(...).
```

</details>

</blockquote></details>
<details>
<summary>Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift (1)</summary><blockquote>

`274-274`: _💤 Low value_

**Consider scoping the post-handshake delay.**

The 200ms settle delay is applied unconditionally to all USB devices, but the comment indicates it's specifically for controllers like Vader 5S. This adds latency to device initialization for controllers that don't need it.



<details>
<summary>♻️ Optional: Scope delay to devices that need it</summary>

```diff
-    try? await Task.sleep(nanoseconds: usbPostHandshakeSettleNs)
+    if endpointConfig.needsSetConfiguration {
+      try? await Task.sleep(nanoseconds: usbPostHandshakeSettleNs)
+    }
```
</details>

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against the current code and only fix it if needed.

In `@Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift` at line 274, The
unconditional await Task.sleep(nanoseconds: usbPostHandshakeSettleNs) in
DevicePipeline should be scoped only to devices that need the 200ms settle
(e.g., Vader 5S). Wrap that call in a conditional that checks a device-specific
predicate (for example use properties on the device object such as
vendorId/productId, modelId, or a helper like needsPostHandshakeSettle(device) )
so only matching devices trigger the delay; keep usbPostHandshakeSettleNs as the
delay constant and add a small lookup or switch (or a per-device flag) to
DevicePipeline to determine applicability.
```

</details>

</blockquote></details>

</blockquote></details>

<details>
<summary>🤖 Prompt for all review comments with AI agents</summary>

```
Verify each finding against the current code and only fix it if needed.

Nitpick comments:
In `@Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift`:
- Line 274: The unconditional await Task.sleep(nanoseconds:
usbPostHandshakeSettleNs) in DevicePipeline should be scoped only to devices
that need the 200ms settle (e.g., Vader 5S). Wrap that call in a conditional
that checks a device-specific predicate (for example use properties on the
device object such as vendorId/productId, modelId, or a helper like
needsPostHandshakeSettle(device) ) so only matching devices trigger the delay;
keep usbPostHandshakeSettleNs as the delay constant and add a small lookup or
switch (or a per-device flag) to DevicePipeline to determine applicability.

In `@Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift`:
- Around line 38-42: The code directly casts entry.inputEndpoint and
entry.outputEndpoint (decoded as Int) to UInt8 when constructing
USBEndpointConfig in the endpoints assignment; add explicit bounds checking
(0...255) for both inputEndpoint and outputEndpoint before converting to UInt8
(e.g., guard or if-let that ensures values are within range) and handle
out-of-range or nil values by skipping this entry or logging an error instead of
silently truncating; update the logic around endpoints[key] =
USBEndpointConfig(...) and the use of entry.needsSetConfiguration to only run
when validated UInt8 values are available.
- Around line 11-12: The static property gipDefault currently constructs a
USBEndpointConfig directly; replace that explicit type with a static/self
reference to satisfy SwiftLint (use Self or .init) so the declaration becomes a
Self-based initializer for USBEndpointConfig; update the expression that creates
the instance (referencing gipDefault and USBEndpointConfig) to use Self(...) or
.init(...) instead of USBEndpointConfig(...).
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

**Run ID**: `b41d3581-a2f5-4565-95ab-a2d7016e492e`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between daeb867ac80f4f80be49750bdd249667d66b8fb7 and 3c6736d2937d041e45542048abfad9c6278098fa.

</details>

<details>
<summary>📒 Files selected for processing (8)</summary>

* `README.md`
* `Sources/OpenJoystickDriverKit/Device/DeviceManager.swift`
* `Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift`
* `Sources/OpenJoystickDriverKit/Protocol/DeviceCatalog.swift`
* `Sources/OpenJoystickDriverKit/Protocol/GIPAuthHandler.swift`
* `Sources/OpenJoystickDriverKit/Protocol/GIPParser.swift`
* `Sources/OpenJoystickDriverKit/Protocol/ParserRegistry.swift`
* `Sources/OpenJoystickDriverKit/Resources/devices.json`

</details>

</details>

<!-- This is an auto-generated comment by CodeRabbit for review status -->


## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-1.patch)
