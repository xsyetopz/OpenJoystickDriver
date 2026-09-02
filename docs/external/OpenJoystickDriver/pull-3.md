# PR #3: feat: Xbox 360 wired parser, GIP LED control, profile, schema, tests

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/3
- **State:** CLOSED
- **Draft:** True
- **Author:** app/copilot-swe-agent
- **Created:** 2026-05-05T17:09:24Z
- **Updated:** 2026-05-05T18:49:48Z
- **Closed:** 2026-05-05T18:49:38Z
- **Merged:** —

## Description

macOS had no physical Xbox 360 USB input parsing, no rumble/LED output for Xbox 360, and no LED control for GIP controllers. This adds the full read/write pipeline for Xbox 360 wired hardware and expands GIP output capability.

## Xbox360Parser (`Protocol/Parsers/Xbox360Parser.swift`)

New `InputParser` conforming type for Xbox 360 wired controllers (class 0xFF, interface 0):

- Parses 20-byte XUSB interrupt-IN reports: buttons (A/B/X/Y, LB/RB, L3/R3, Start/Back/Guide), 4+4 diagonal dpad, separate LT/RT (0–1.0), signed sticks with Y-inversion matching OJD convention
- Silently drops non-`0x00` report types (wireless receiver connection events)
- Change-detection: emits events only on state delta, consistent with GIP/DS4 parsers
- `sendRumble(handle:left:right:)` — 8-byte OUT report to EP 0x01 (Xbox 360 has no trigger motors)
- `sendLED(handle:pattern:)` — 3-byte OUT with `Xbox360LEDPattern` enum (all 16 hardware patterns)

```swift
// DevicePipeline.sendRumble now dispatches to either parser:
if let gip = parser as? GIPParser {
    try gip.sendRumble(handle: handle, left: left, right: right, ltMotor: lt, rtMotor: rt)
} else if let x360 = parser as? Xbox360Parser {
    try x360.sendRumble(handle: handle, left: left, right: right)
}
```

## GIP LED control (`GIPParser.sendLED`)

Adds `sendLED(handle:mode:brightness:)` alongside the existing `sendRumble()`, using CMD `0x0A`. Modes: `0x00` off, `0x01` steady, `0x02` blink, `0x03` pulse; brightness `0x00–0x14`.

## Catalog / registry wiring

- `ParserRegistry`: dispatches `"Xbox360"` driver name to `Xbox360Parser`
- `DeviceCatalog`: maps `"Xbox360"` → `.xbox360` protocol variant
- `microsoft-xbox360-wired.json`: VID 1118 (`0x045E`), PID 654 (`0x028E`), EP in=129, out=1

## Schema / validator

- `Resources/Schemas/Protocols/xbox360.schema.json`: new protocol schema (`driver: "Xbox360"`, variants `xbox360`/`unknown`)
- `controller-profile.schema.json`: Xbox360 added to protocol `oneOf`
- `ojd-validate-profiles.py`: `Xbox360` driver recognized with its own variant/flag sets; all 5 profiles still validate clean

## Files

- `Resources/Schemas/Protocols/xbox360.schema.json` (+37/-0, ADDED)
- `Resources/Schemas/controller-profile.schema.json` (+3/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift` (+6/-2, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/Catalog/DeviceCatalog.swift` (+1/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/Catalog/ParserRegistry.swift` (+1/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/GIP/GIPParser.swift` (+13/-0, MODIFIED)
- `Sources/OpenJoystickDriverKit/Protocol/Parsers/Xbox360Parser.swift` (+251/-0, ADDED)
- `Sources/OpenJoystickDriverKit/Resources/Controllers/microsoft-xbox360-wired.json` (+32/-0, ADDED)
- `Tests/OpenJoystickDriverKitTests/Xbox360ParserTests.swift` (+296/-0, ADDED)
- `scripts/ojd-validate-profiles.py` (+4/-0, MODIFIED)

## Commits

- `344488071f26` feat: add Xbox360Parser, GIP LED control, wired Xbox 360 profile and …
- `00fbd49f97ca` fix: remove duplicate state mutation from Xbox360Parser.parseSticks

## Conversation

### xsyetopz — 2026-05-05T18:49:38Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/3#issuecomment-4382088803)

Resolved as of https://github.com/xsyetopz/OpenJoystickDriver/commit/d1a87fc5941a35826050ea8424681b8388ee0e25

## Reviews

_No reviews._

## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-3.patch)
